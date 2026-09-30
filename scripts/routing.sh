#!/usr/bin/env bash
# Uso: routing.sh <static|rip|ospf|rttls|stop>
# Para QUALQUER mecanismo de roteamento (BIRD e RTT-LS) e inicia só o modo escolhido.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=${1:?uso: $0 static|rip|ospf|rttls|stop}

for n in 1 2 3 4 5; do
  podman exec router-r$n sh -c 'pkill -x bird || true; pkill -f "[r]ttls.py" || true; sleep 0.3; ip route flush proto 99 || true'
done
sleep 1

if [ "$MODE" = stop ]; then echo "roteamento parado"; exit 0; fi

if [ "$MODE" = rttls ]; then
  for n in 1 2 3 4 5; do
    podman exec -d router-r$n sh -c 'exec python3 /configs/rttls/rttls.py > /var/log/rttls.log 2>&1'
  done
  echo "modo rttls ativo nos 5 roteadores"
  exit 0
fi

for n in 1 2 3 4 5; do
  [ -f "$ROOT/configs/$MODE/r$n.conf" ] || { echo "falta configs/$MODE/r$n.conf"; exit 1; }
done
for n in 1 2 3 4 5; do
  podman exec router-r$n sh -c "mkdir -p /run/bird && bird -c /configs/$MODE/r$n.conf -s /run/bird/bird.ctl"
done
echo "modo $MODE ativo nos 5 roteadores"
