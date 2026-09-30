#!/usr/bin/env bash
# Uso: routing.sh <static|rip|ospf|stop>
# Para o BIRD nos 5 roteadores e reinicia com a config do modo escolhido.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=${1:?uso: $0 static|rip|ospf|stop}

for n in 1 2 3 4 5; do
  podman exec router-r$n sh -c 'pkill -x bird || true'
done
sleep 1
if [ "$MODE" = stop ]; then echo "roteamento parado"; exit 0; fi

for n in 1 2 3 4 5; do
  [ -f "$ROOT/configs/$MODE/r$n.conf" ] || { echo "falta configs/$MODE/r$n.conf"; exit 1; }
done
for n in 1 2 3 4 5; do
  podman exec router-r$n sh -c "mkdir -p /run/bird && bird -c /configs/$MODE/r$n.conf -s /run/bird/bird.ctl"
done
echo "modo $MODE ativo nos 5 roteadores"
