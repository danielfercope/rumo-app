#!/usr/bin/env bash
# Publica o frontend em producao.
#
#   deploy_frontend.sh web   -> build do Flutter Web, envio pro S3 e sync na EC2
#   deploy_frontend.sh apk   -> build do APK assinado, envio pro S3 e sync na EC2
#
# O build roda aqui (a EC2 t3.micro nao aguenta compilar Flutter); a EC2 so
# sincroniza o bucket pro volume que o Caddy serve (docker-compose.prod.yml).
#
# Variaveis: INSTANCE_ID e ARTIFACTS_BUCKET (obrigatorias); AWS_REGION
# (padrao us-east-1, onde a stack rumo-app-backend roda) e API_BASE_URL
# (padrao https://rumo-app.duckdns.org).

set -euo pipefail

target="${1:-}"
: "${INSTANCE_ID:?defina INSTANCE_ID (ex.: i-0123...)}"
: "${ARTIFACTS_BUCKET:?defina ARTIFACTS_BUCKET (saida BucketName da stack rumo-app-artifacts)}"
region="${AWS_REGION:-us-east-1}"
api_base_url="${API_BASE_URL:-https://rumo-app.duckdns.org}"

cd "$(dirname "$0")/../.."

[ -f .env ] || { echo "ERRO: .env ausente (ver CLAUDE.md > Variaveis de ambiente)" >&2; exit 1; }

remote_sync() {
  # $1 = comando executado na EC2 via SSM (sem SSH)
  local command_id
  command_id=$(aws ssm send-command --region "$region" \
    --instance-ids "$INSTANCE_ID" --document-name AWS-RunShellScript \
    --parameters "commands=[\"$1\"]" \
    --query Command.CommandId --output text)
  aws ssm wait command-executed --region "$region" \
    --command-id "$command_id" --instance-id "$INSTANCE_ID"
  aws ssm get-command-invocation --region "$region" \
    --command-id "$command_id" --instance-id "$INSTANCE_ID" \
    --query Status --output text
}

case "$target" in
  web)
    [ -f web/env.js ] || { echo "ERRO: web/env.js ausente (copie web/env.js.example e preencha a chave do Maps)" >&2; exit 1; }
    flutter build web --release --dart-define-from-file=.env \
      --dart-define="API_BASE_URL=$api_base_url"
    aws s3 sync build/web "s3://$ARTIFACTS_BUCKET/web" --delete --region "$region"
    remote_sync "mkdir -p /mnt/rumo-data/web && aws s3 sync s3://$ARTIFACTS_BUCKET/web /mnt/rumo-data/web --delete --region $region"
    echo "Frontend publicado em $api_base_url/"
    ;;
  apk)
    [ -f android/key.properties ] || { echo "ERRO: android/key.properties ausente — sem ele o APK de release nao e assinado" >&2; exit 1; }
    [ -f android/secrets.properties ] || { echo "ERRO: android/secrets.properties ausente (ver android/secrets.properties.example) — sem a chave o mapa fica em branco" >&2; exit 1; }
    flutter build apk --release --dart-define-from-file=.env \
      --dart-define="API_BASE_URL=$api_base_url"
    aws s3 cp build/app/outputs/flutter-apk/app-release.apk \
      "s3://$ARTIFACTS_BUCKET/downloads/rumo.apk" \
      --content-type application/vnd.android.package-archive --region "$region"
    remote_sync "mkdir -p /mnt/rumo-data/downloads && aws s3 cp s3://$ARTIFACTS_BUCKET/downloads/rumo.apk /mnt/rumo-data/downloads/rumo.apk --region $region"
    echo "APK disponivel em $api_base_url/download/rumo.apk"
    ;;
  *)
    echo "uso: $0 web|apk" >&2
    exit 2
    ;;
esac
