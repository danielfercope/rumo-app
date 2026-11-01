#!/usr/bin/env bash
# Liga a sincronizacao CRM -> banco em producao, em etapas separadas.
#
#   enable_crm_sync.sh migrate    aplica db/schema/008_crm_sync.sql no banco de producao
#   enable_crm_sync.sh config     grava GEOCODING_API_KEY (+ CRM_SYNC_ENABLED=false) no
#                                 Secrets Manager e atualiza o infra/.env da EC2
#   enable_crm_sync.sh backfill   importa o historico do CRM (uma vez; idempotente)
#   enable_crm_sync.sh enable     liga o job (CRM_SYNC_ENABLED=true) e reinicia o backend
#   enable_crm_sync.sh status     mostra logs do job, marca d'agua e contagens (so leitura)
#
# Ordem: migrate -> config -> backfill -> enable. Rode `status` quando quiser.
#
# Variaveis: INSTANCE_ID (obrigatoria); AWS_REGION (padrao us-east-1);
# GEOCODING_API_KEY (so no `config`); DRY_RUN=1 mostra o que seria feito sem executar.
#
# Segredos: nenhum valor e impresso. O segredo do Secrets Manager e manipulado
# por um arquivo temporario 600 (apagado ao sair), nunca pela linha de comando.

set -euo pipefail

step="${1:-}"
: "${INSTANCE_ID:?defina INSTANCE_ID (ex.: i-0123...)}"
region="${AWS_REGION:-us-east-1}"
secret_id="rumo-app/backend-env"
compose="docker compose -f docker-compose.backend.yml -f docker-compose.prod.yml --env-file infra/.env"

dry() { [ -n "${DRY_RUN:-}" ]; }

# Roda comandos na EC2 via SSM (sem SSH) e falha se o status nao for Success.
remote() {
  local json command_id status
  json=$(python3 -c 'import json,sys; print(json.dumps({"commands": sys.argv[1:]}))' "$@")
  if dry; then
    echo "[dry-run] SSM em $INSTANCE_ID:"; printf '  %s\n' "$@"; return 0
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

# Regrava o infra/.env da EC2 a partir do Secrets Manager (igual ao UserData) e
# recria so o backend, que e quem le essas variaveis.
refresh_env_and_restart_backend() {
  remote \
    "set -e" \
    "cd /opt/rumo-app" \
    "aws secretsmanager get-secret-value --region $region --secret-id $secret_id --query SecretString --output text | jq -r 'to_entries[]|\"\\(.key)=\\(.value)\"' > infra/.env.new" \
    "chmod 600 infra/.env.new && mv infra/.env.new infra/.env" \
    "$compose up -d --no-deps backend" \
    "sleep 5; $compose ps --format '{{.Service}} {{.Status}}'"
}

# Soma chaves ao JSON do segredo (preserva as demais) sem imprimir valores.
# uso: update_secret '<filtro jq>'  (valores sensiveis via $ENV.NOME, nunca --arg)
update_secret() {
  local filter="$1"; shift
  if dry; then echo "[dry-run] atualizaria $secret_id com o filtro jq: $filter"; return 0; fi
  local tmp; umask 077; tmp=$(mktemp)
  # Aspas duplas: $tmp expande AGORA. Com aspas simples o trap rodaria ao sair do
  # script, quando a variavel local ja nao existe, e o arquivo (com o segredo) ficaria.
  trap "rm -f '$tmp'" EXIT
  aws secretsmanager get-secret-value --region "$region" --secret-id "$secret_id" \
    --query SecretString --output text | jq "$@" "$filter" > "$tmp"
  aws secretsmanager put-secret-value --region "$region" --secret-id "$secret_id" \
    --secret-string "file://$tmp" --query VersionId --output text > /dev/null
  echo "Segredo $secret_id atualizado."
}

case "$step" in
  migrate)
    remote \
      "set -e" \
      "cd /opt/rumo-app" \
      "$compose exec -T db psql -U postgres -d rumo -v ON_ERROR_STOP=1 < db/schema/008_crm_sync.sql" \
      "$compose exec -T db psql -U postgres -d rumo -c \"NOTIFY pgrst, 'reload schema';\"" \
      "echo '--- verificacao:'" \
      "$compose exec -T db psql -U postgres -d rumo -tAc \"select 'tabelas=' || (select string_agg(table_name, ',' order by table_name) from information_schema.tables where table_schema='public' and table_name like 'crm_sync%') || ' | papel_crm_sync=' || (select count(*) from pg_roles where rolname='crm_sync') || ' | authenticator_herda=' || pg_has_role('authenticator','crm_sync','member')\""
    ;;
  config)
    : "${GEOCODING_API_KEY:?defina GEOCODING_API_KEY (chave de SERVIDOR da Google Geocoding API)}"
    # $ENV le a variavel de ambiente: a chave nao aparece na linha de comando do jq.
    update_secret '. + {GEOCODING_API_KEY: $ENV.GEOCODING_API_KEY, CRM_SYNC_ENABLED: "false"}'
    refresh_env_and_restart_backend
    ;;
  backfill)
    remote \
      "set -e" \
      "cd /opt/rumo-app" \
      "rc=0; $compose exec -T backend python -m app.scripts.crm_backfill > /tmp/crm_backfill.log 2>&1 || rc=\$?" \
      "tail -25 /tmp/crm_backfill.log; exit \$rc"
    ;;
  enable)
    update_secret '. + {CRM_SYNC_ENABLED: "true"}'
    refresh_env_and_restart_backend
    echo "Job ligado. Acompanhe com: $0 status"
    ;;
  status)
    remote \
      "cd /opt/rumo-app" \
      "echo '--- logs do job (ultimos 30 min):'; $compose logs --since 30m backend 2>&1 | grep -i 'crm_sync\\|sincroniza' | tail -15 || true" \
      "echo '--- banco:'; $compose exec -T db psql -U postgres -d rumo -tAc \"select 'marca_dagua=' || coalesce((select last_crm_id::text || ' (' || coalesce(last_status,'-') || ', ' || coalesce(last_run_at::text,'-') || ')' from crm_sync_state where key='companies'),'nao inicializada') || ' | pendentes=' || (select count(*) from crm_sync_pending) || ' | empresas=' || (select count(*) from companies) || ' | vinculadas_ao_crm=' || (select count(*) from company_crm_sync)\""
    ;;
  *)
    echo "uso: $0 migrate|config|backfill|enable|status" >&2
    exit 2
    ;;
esac
