#!/bin/sh

set -eu

is_port_in_use() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -n -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi

  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$1" >/dev/null 2>&1
    return
  fi

  echo "Erro: preciso de 'lsof' ou 'nc' para verificar portas em uso." >&2
  exit 1
}

START_PORT="${1:-4000}"
PORT="$START_PORT"

while is_port_in_use "$PORT"; do
  echo "Porta $PORT ocupada, tentando a próxima..."
  PORT=$((PORT + 1))
done

echo "Iniciando Phoenix na porta $PORT"
exec env PORT="$PORT" mix phx.server
