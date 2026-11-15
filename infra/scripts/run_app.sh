#!/usr/bin/env bash
# Roda o app Flutter apontando pro backend local, sem editar IP no .env.
#
#   make run                      # pergunta o dispositivo (flutter run)
#   make run DEVICE=chrome        # Web
#   make run DEVICE=<id>          # celular/emulador (ver `flutter devices`)
#   API_BASE_URL=https://rumo-app.duckdns.org make run   # outro backend
#
# Garante o Docker e o backend no ar (make db-up) e passa API_BASE_URL com o IP
# atual da máquina na rede — o que um celular/emulador consegue alcançar. Vale
# também pro Chrome, então não importa se o IP mudou desde a última vez.
set -euo pipefail
cd "$(dirname "$0")/../.."

[ -f .env ] || { echo "Falta o .env na raiz do projeto (ver README, 'Variáveis de ambiente')." >&2; exit 1; }

host_ip() {
  local ip=""
  if [ "$(uname)" = Darwin ]; then
    local iface
    iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    [ -n "$iface" ] && ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
  else
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
  fi
  echo "${ip:-localhost}"
}

api_base_url="${API_BASE_URL:-}"
if [ -z "$api_base_url" ]; then
  if ! docker info >/dev/null 2>&1; then
    [ "$(uname)" = Darwin ] && open -a Docker
    echo "Aguardando o Docker..."
    for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 2; done
    docker info >/dev/null 2>&1 || { echo "O Docker não está rodando." >&2; exit 1; }
  fi
  make db-up
  api_base_url="http://$(host_ip):8080"
fi

echo "Backend: $api_base_url"
device_args=()
[ -n "${DEVICE:-}" ] && device_args=(-d "$DEVICE")

# O --dart-define depois do --dart-define-from-file tem precedência sobre o .env.
exec flutter run "${device_args[@]+"${device_args[@]}"}" \
  --dart-define-from-file=.env \
  --dart-define="API_BASE_URL=$api_base_url" \
  ${FLUTTER_ARGS:-}
