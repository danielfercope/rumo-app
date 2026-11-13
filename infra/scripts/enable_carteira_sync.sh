#!/usr/bin/env bash
# Liga a carteira por organizacao (CRM por organizacao + prioridade dos leads)
# em producao, em etapas separadas.
#
#   enable_carteira_sync.sh migrate  leva o repositorio da EC2 para a BRANCH (padrao main) e aplica
#                                    db/schema/007..014, 017 e 018 no banco de producao
#   enable_carteira_sync.sh config   garante no Secrets Manager a chave de cifra dos tokens
#                                    (CRM_TOKEN_ENCRYPTION_KEY, gerada UMA vez) e a
#                                    GEOCODING_API_KEY, com o job ainda DESLIGADO
#   enable_carteira_sync.sh enable   liga o job (CRM_CONNECTIONS_SYNC_ENABLED=true)
#   enable_carteira_sync.sh status   conexoes, carteira, prioridade e logs (so leitura)
#
# Ordem: migrate (ja atualiza o codigo da EC2 pra main: as migracoes sao lidas de la)
#        -> `make deploy` (reconstroi a imagem do Backend, que agora usa numpy)
#        -> config -> enable -> deploy-web/deploy-apk (o app novo chama o schema novo).
#
# Variaveis: INSTANCE_ID (obrigatoria); AWS_REGION (padrao us-east-1);
# GEOCODING_API_KEY (so no `config`, e so se o segredo ainda nao a tiver);
# DRY_RUN=1 mostra o que seria feito sem executar nada.
#
# Segredos: nenhum valor e impresso. O segredo do Secrets Manager e manipulado por
# um arquivo temporario 600 (apagado ao sair); valores novos entram no jq por
# variavel de ambiente ($ENV), nunca pela linha de comando.
#
# ATENCAO: perder ou trocar CRM_TOKEN_ENCRYPTION_KEY obriga TODAS as organizacoes a
# reconectar o CRM (os tokens ficam cifrados no banco). Por isso o `config` so a
# cria quando ela nao existe e nunca a sobrescreve.

set -euo pipefail
# O AWS CLI abre um pager (less) em saidas longas e o script ficaria parado esperando tecla.
export AWS_PAGER=""

step="${1:-}"
: "${INSTANCE_ID:?defina INSTANCE_ID (ex.: i-0123...)}"
region="${AWS_REGION:-us-east-1}"
branch="${BRANCH:-main}"
secret_id="rumo-app/backend-env"
compose="docker compose -f docker-compose.backend.yml -f docker-compose.prod.yml --env-file infra/.env"
psql="$compose exec -T db psql -U postgres -d rumo"

# Migracoes, na ordem. O banco de producao so aplica db/schema/ sozinho no primeiro
# boot, entao ele fica na versao da branch da epoca (001-006): a carteira precisa
# tambem da 007 (grupos/organizacoes). A 008 cria o papel crm_sync que as demais usam.
# Todas sao idempotentes (IF NOT EXISTS / OR REPLACE), entao reaplicar e seguro.
migrations=(
  007_groups.sql
  008_crm_sync.sql
  009_carteira.sql
  010_search_companies_carteira.sql
  011_carteira_pendencias.sql
  012_crm_sync_group_members.sql
  013_carteira_interacao.sql
  014_carteira_prioridade.sql
  017_progresso_sincronizacao.sql
  018_enriquecimento_cache.sql
)

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
# recria so o backend, que e quem le essas variaveis. NAO reconstroi a imagem:
# isso e o `make deploy`.
refresh_env_and_restart_backend() {
  remote \
    "set -e" \
    "cd /opt/rumo-app" \
    "aws secretsmanager get-secret-value --region $region --secret-id $secret_id --query SecretString --output text | jq -r 'to_entries[]|\"\\(.key)=\\(.value)\"' > infra/.env.new" \
    "chmod 600 infra/.env.new && mv infra/.env.new infra/.env" \
    "$compose up -d --no-deps backend" \
    "sleep 5; $compose ps --format '{{.Service}} {{.Status}}'"
}

# Le o segredo e imprime so se a chave existe (true/false), nunca o valor.
secret_has() {
  aws secretsmanager get-secret-value --region "$region" --secret-id "$secret_id" \
    --query SecretString --output text | jq -r --arg k "$1" 'has($k)'
}

# Aplica um filtro jq ao JSON do segredo (preserva as demais chaves) sem imprimir valores.
# Valores sensiveis chegam por variavel de ambiente ($ENV.NOME), nunca por --arg.
update_secret() {
  local filter="$1"
  if dry; then echo "[dry-run] atualizaria $secret_id com o filtro jq: $filter"; return 0; fi
  local tmp; umask 077; tmp=$(mktemp)
  # Aspas duplas: $tmp expande AGORA. Com aspas simples o trap rodaria ao sair do
  # script, quando a variavel local ja nao existe, e o arquivo (com o segredo) ficaria.
  trap "rm -f '$tmp'" EXIT
  aws secretsmanager get-secret-value --region "$region" --secret-id "$secret_id" \
    --query SecretString --output text | jq "$filter" > "$tmp"
  aws secretsmanager put-secret-value --region "$region" --secret-id "$secret_id" \
    --secret-string "file://$tmp" --query VersionId --output text > /dev/null
  echo "Segredo $secret_id atualizado."
}

case "$step" in
  migrate)
    cmds=(
      "set -e"
      "cd /opt/rumo-app"
      # as migracoes sao lidas do repositorio da EC2: leva ele pra branch certa primeiro
      "git fetch --depth 1 origin $branch && git checkout -B $branch FETCH_HEAD"
      "for f in ${migrations[*]}; do test -f db/schema/\$f || { echo \"ERRO: db/schema/\$f nao existe em $branch\"; exit 1; }; done"
      # pre-requisito: o schema base (001-006), que a 007 em diante referencia.
      # (Nao usar CASE ... 1/0: o PostgreSQL avalia a constante no planejamento e falha sempre.)
      "[ \"\$($psql -tAc \"select count(*) from pg_tables where schemaname='public' and tablename in ('profiles','companies')\")\" = 2 ] || { echo 'ERRO: faltam profiles/companies (migracoes 001-006). Abortado, nada aplicado.'; exit 1; }"
    )
    for f in "${migrations[@]}"; do
      cmds+=("echo 'aplicando $f'" "$psql -v ON_ERROR_STOP=1 < db/schema/$f")
    done
    cmds+=(
      "$psql -c \"NOTIFY pgrst, 'reload schema';\""
      "echo '--- verificacao:'"
      "$psql -tAc \"select 'tabelas=' || (select count(*) from information_schema.tables where table_schema='public' and table_name in ('carteira_empresas','crm_conexoes','sincronizacoes','carteira_pendencias','prioridade_modelos','carteira_prioridade')) || '/6 | papel_crm_sync=' || (select count(*) from pg_roles where rolname='crm_sync') || ' | colunas_interacao=' || (select count(*) from information_schema.columns where table_name='carteira_empresas' and column_name in ('crm_criado_em','ultima_interacao_em','num_interacoes')) || '/3'\""
    )
    remote "${cmds[@]}"
    ;;
  config)
    # Gera a chave de cifra so se o segredo ainda nao a tiver. Nunca sobrescreve.
    if dry; then has_key=false; has_geo=false; else
      has_key=$(secret_has CRM_TOKEN_ENCRYPTION_KEY); has_geo=$(secret_has GEOCODING_API_KEY)
    fi
    if [ "$has_geo" = "false" ]; then
      : "${GEOCODING_API_KEY:?o segredo ainda nao tem GEOCODING_API_KEY: defina-a (chave de SERVIDOR da Google Geocoding API)}"
    fi
    if [ "$has_key" = "true" ]; then
      echo "CRM_TOKEN_ENCRYPTION_KEY ja existe no segredo: mantida (nao e regenerada)."
    else
      echo "CRM_TOKEN_ENCRYPTION_KEY nao existe: gerando uma chave nova (32 bytes, base64 url-safe)."
      echo "GUARDE um backup do segredo: perder essa chave obriga todas as organizacoes a reconectar."
    fi
    (
      # Fernet = 32 bytes aleatorios em base64 url-safe. Fica so no ambiente deste subshell.
      NEW_FERNET_KEY=$(python3 -c 'import base64,os;print(base64.urlsafe_b64encode(os.urandom(32)).decode())')
      export NEW_FERNET_KEY GEOCODING_API_KEY="${GEOCODING_API_KEY:-}"
      update_secret '. as $s | $s + {
        CRM_TOKEN_ENCRYPTION_KEY: ($s.CRM_TOKEN_ENCRYPTION_KEY // $ENV.NEW_FERNET_KEY),
        GEOCODING_API_KEY: ($s.GEOCODING_API_KEY // $ENV.GEOCODING_API_KEY),
        CRM_CONNECTIONS_SYNC_ENABLED: ($s.CRM_CONNECTIONS_SYNC_ENABLED // "false")
      }'
    )
    refresh_env_and_restart_backend
    ;;
  enable)
    if ! dry; then
      for k in CRM_TOKEN_ENCRYPTION_KEY GEOCODING_API_KEY; do
        [ "$(secret_has $k)" = "true" ] || { echo "ERRO: falta $k no segredo. Rode primeiro: $0 config" >&2; exit 1; }
      done
    fi
    # a imagem antiga do Backend nao tem numpy/cryptography: o job nao subiria
    remote \
      "cd /opt/rumo-app" \
      "$compose exec -T backend python -c 'import numpy, cryptography; print(\"imagem ok: numpy\", numpy.__version__)'"
    update_secret '. + {CRM_CONNECTIONS_SYNC_ENABLED: "true"}'
    refresh_env_and_restart_backend
    echo "Job ligado. Acompanhe com: $0 status"
    ;;
  status)
    remote \
      "cd /opt/rumo-app" \
      "echo '--- logs do job (ultimos 30 min):'; $compose logs --since 30m backend 2>&1 | grep -iE 'carteira|sincroniza|prioridade|CRM_CONNECTIONS' | tail -20 || true" \
      "echo '--- banco:'; $psql -tAc \"select 'conexoes=' || (select count(*) from crm_conexoes) || ' (ativas=' || (select count(*) from crm_conexoes where situacao='ativa') || ', erro=' || (select count(*) from crm_conexoes where situacao='erro') || ') | carteira=' || (select count(*) from carteira_empresas) || ' | pendencias=' || (select count(*) from carteira_pendencias) || ' | prioridade_leads=' || (select count(*) from carteira_prioridade) || ' | modelos=' || (select count(*) from prioridade_modelos)\""
    ;;
  *)
    echo "uso: $0 migrate|config|enable|status" >&2
    exit 2
    ;;
esac
