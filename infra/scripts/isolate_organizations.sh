#!/usr/bin/env bash
# Isolamento entre organizacoes em producao (db/schema/015_isolamento_organizacao.sql).
#
#   isolate_organizations.sh migrate        leva a EC2 pra BRANCH (padrao main) e aplica a 015
#   isolate_organizations.sh create-org <nome> <email-do-admin>
#                                           cria a organizacao dona da base atual (ex.: Rumo) e entrega
#                                           a um administrador que ja entrou no app uma vez. Idempotente
#                                           (nao duplica); imprime o UUID, NAO o codigo de convite
#   isolate_organizations.sh legacy <uuid>  associa a base SEM DONO (importada pelo sync antigo ou
#                                           cadastrada antes das organizacoes) a organizacao <uuid>.
#                                           Com COUNT_ONLY=1 so CONTA (le o banco, nao altera nada).
#   isolate_organizations.sh config <uuid>  grava CRM_LEGACY_GROUP_ID=<uuid> (a organizacao dona do
#                                           CRM global, unica que usa notas/contatos no detalhe da
#                                           empresa) e desliga o sync antigo de conta unica
#                                           (CRM_SYNC_ENABLED=false); reinicia o backend
#   isolate_organizations.sh verify         prova, SO LEITURA, que um usuario sem organizacao nao
#                                           ve nenhuma empresa nem consegue buscar
#
# ORDEM (o app antigo deixa de funcionar assim que a 015 entra: publique o novo logo em seguida):
#   1. make deploy                          backend novo (/crm e /company-lookup exigem organizacao)
#   2. isolate_organizations.sh migrate
#   2b. isolate_organizations.sh create-org Rumo <email-do-admin>     (anote o UUID impresso)
#   3. isolate_organizations.sh legacy <uuid>   (antes: COUNT_ONLY=1 pra ver quantas empresas)
#   4. isolate_organizations.sh config <uuid>
#   5. isolate_organizations.sh verify
#   6. make deploy-web / deploy-apk         (o build precisa de WEBHOOK_CRM_GROUP_ID no .env se a
#                                            organizacao <uuid> deve continuar enviando cadastros
#                                            ao webhook de CRM; sem isso o webhook fica desligado)
#
# Sem passo 3, as empresas atuais ficam INVISIVEIS pra todos (nada e apagado: basta rodar o `legacy`).
#
# Variaveis: INSTANCE_ID (obrigatoria); AWS_REGION (padrao us-east-1); BRANCH (padrao main);
# DRY_RUN=1 mostra o que seria feito sem executar nada. Nenhum segredo e impresso.

set -euo pipefail
export AWS_PAGER=""

step="${1:-}"
arg="${2:-}"
: "${INSTANCE_ID:?defina INSTANCE_ID (ex.: i-0123...)}"
region="${AWS_REGION:-us-east-1}"
branch="${BRANCH:-main}"
secret_id="rumo-app/backend-env"
compose="docker compose -f docker-compose.backend.yml -f docker-compose.prod.yml --env-file infra/.env"
psql="$compose exec -T db psql -U postgres -d rumo"

dry() { [ -n "${DRY_RUN:-}" ]; }

uuid_ok() { [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; }

remote() {
  local json command_id status
  json=$(python3 -c 'import json,sys; print(json.dumps({"commands": sys.argv[1:]}))' "$@")
  if dry; then
    # o SSM junta os comandos num script, uma linha apos a outra: imprime igual
    echo "[dry-run] SSM em $INSTANCE_ID:"; printf '%s\n' "$@"; return 0
  fi
  command_id=$(aws ssm send-command --region "$region" --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript --parameters "$json" --timeout-seconds 900 \
    --query Command.CommandId --output text)
  aws ssm wait command-executed --region "$region" --command-id "$command_id" \
    --instance-id "$INSTANCE_ID" || true
  aws ssm get-command-invocation --region "$region" --command-id "$command_id" \
    --instance-id "$INSTANCE_ID" \
    --query '[Status,StandardOutputContent,StandardErrorContent]' --output text
  status=$(aws ssm get-command-invocation --region "$region" --command-id "$command_id" \
    --instance-id "$INSTANCE_ID" --query Status --output text)
  [ "$status" = "Success" ] || { echo "ERRO: etapa terminou com status $status" >&2; exit 1; }
}

update_secret() {
  local filter="$1"
  if dry; then echo "[dry-run] atualizaria $secret_id com o filtro jq: $filter"; return 0; fi
  local tmp; umask 077; tmp=$(mktemp)
  trap "rm -f '$tmp'" EXIT
  aws secretsmanager get-secret-value --region "$region" --secret-id "$secret_id" \
    --query SecretString --output text | jq "$filter" > "$tmp"
  aws secretsmanager put-secret-value --region "$region" --secret-id "$secret_id" \
    --secret-string "file://$tmp" --query VersionId --output text > /dev/null
  echo "Segredo $secret_id atualizado."
}

refresh_env_and_restart_backend() {
  remote \
    "set -e" \
    "cd /opt/rumo-app" \
    "aws secretsmanager get-secret-value --region $region --secret-id $secret_id --query SecretString --output text | jq -r 'to_entries[]|\"\\(.key)=\\(.value)\"' > infra/.env.new" \
    "chmod 600 infra/.env.new && mv infra/.env.new infra/.env" \
    "$compose up -d --no-deps backend" \
    "sleep 5; $compose ps --format '{{.Service}} {{.Status}}'"
}

case "$step" in
  migrate)
    remote \
      "set -e" \
      "cd /opt/rumo-app" \
      "git fetch --depth 1 origin $branch && git checkout -B $branch FETCH_HEAD" \
      "test -f db/schema/015_isolamento_organizacao.sql || { echo 'ERRO: 015 nao existe em $branch'; exit 1; }" \
      "[ \"\$($psql -tAc \"select count(*) from pg_tables where schemaname='public' and tablename in ('carteira_empresas','groups','group_members')\")\" = 3 ] || { echo 'ERRO: faltam carteira_empresas/groups/group_members (migracoes 007-014). Abortado, nada aplicado.'; exit 1; }" \
      "$psql -v ON_ERROR_STOP=1 < db/schema/015_isolamento_organizacao.sql" \
      "echo '--- verificacao (policies de companies):'" \
      "$psql -tAc \"select string_agg(policyname || ' [' || cmd || ']', ', ' order by policyname) from pg_policies where schemaname='public' and tablename='companies' and 'web_user' = any(roles)\"" \
      "$psql -tAc \"select 'funcoes=' || count(*) || '/3' from pg_proc where pronamespace='public'::regnamespace and proname in ('company_in_my_orgs','register_company','portfolio_has_cnpj')\""
    echo "Esperado: so 'companies_select_org [SELECT]' e funcoes=3/3."
    ;;
  create-org)
    org_name="$arg"; admin_email="${3:-}"
    [[ "$org_name" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]{0,60}$ ]] || { echo "uso: $0 create-org <nome (letras, numeros, espaco . _ -)> <email-do-admin>" >&2; exit 2; }
    [[ "$admin_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || { echo "uso: $0 create-org <nome> <email-do-admin>" >&2; exit 2; }
    remote \
      "set -e" \
      "cd /opt/rumo-app" \
      "test -f db/ops/create_organization.sql || { echo 'ERRO: rode migrate antes (atualiza o repositorio da EC2)'; exit 1; }" \
      "$psql -v ON_ERROR_STOP=1 -v org_name='$org_name' -v admin_email='$admin_email' < db/ops/create_organization.sql"
    echo "Use o UUID acima em: $0 legacy <uuid> e $0 config <uuid>"
    ;;
  legacy)
    uuid_ok "$arg" || { echo "uso: $0 legacy <uuid-da-organizacao>" >&2; exit 2; }
    # COUNT_ONLY=1 = so CONTA (le o banco, nao altera): o .sql respeita :dry_run.
    # (DRY_RUN=1 continua significando "nao executa nada": so mostra os comandos.)
    dry_flag=0; [ -n "${COUNT_ONLY:-}" ] && dry_flag=1
    remote \
      "set -e" \
      "cd /opt/rumo-app" \
      "test -f db/ops/assign_legacy_companies.sql || { echo 'ERRO: rode migrate antes (atualiza o repositorio da EC2)'; exit 1; }" \
      "$psql -v ON_ERROR_STOP=1 -v group_id=$arg -v dry_run=$dry_flag < db/ops/assign_legacy_companies.sql" \
      "$psql -tAc \"select 'carteira da organizacao agora: ' || count(*) from carteira_empresas where group_id='$arg'\""
    ;;
  config)
    uuid_ok "$arg" || { echo "uso: $0 config <uuid-da-organizacao-dona-do-crm-global>" >&2; exit 2; }
    update_secret ". + {CRM_LEGACY_GROUP_ID: \"$arg\", CRM_SYNC_ENABLED: \"false\"}"
    refresh_env_and_restart_backend
    echo "CRM_LEGACY_GROUP_ID definido e sync antigo (conta unica) desligado."
    ;;
  verify)
    # SO LEITURA: simula um usuario SEM organizacao (claim 'sub' inexistente) com o papel que o
    # PostgREST usa e confere que ele nao ve nada. Tudo numa transacao com ROLLBACK.
    remote \
      "set -e" \
      "cd /opt/rumo-app" \
      "$psql -v ON_ERROR_STOP=1 -q -tA <<'SQL'
BEGIN;
SET LOCAL ROLE web_user;
SELECT set_config('request.jwt.claims', '{\"sub\":\"__verificacao_sem_organizacao__\"}', true) \\gset
SELECT 'empresas_visiveis=' || count(*) FROM public.companies;
SELECT 'perfil_financeiro_visivel=' || count(*) FROM public.company_financial_profile;
SELECT 'contatos_visiveis=' || count(*) FROM public.company_contacts;
SELECT 'vinculos_crm_visiveis=' || count(*) FROM public.company_crm_sync;
DO \$\$ BEGIN
  BEGIN
    PERFORM * FROM public.search_companies();
    RAISE EXCEPTION 'FALHA: search_companies sem organizacao deveria recusar';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF;
    RAISE NOTICE 'busca_sem_organizacao=recusada (%)', SQLERRM;
  END;
END \$\$;
ROLLBACK;
SQL" \
      "echo '--- esperado: todas as contagens = 0 e a busca recusada.'"
    ;;
  *)
    echo "uso: $0 migrate|create-org <nome> <email>|legacy <uuid>|config <uuid>|verify" >&2
    exit 2
    ;;
esac
