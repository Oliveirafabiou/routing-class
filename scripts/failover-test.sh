#!/usr/bin/env bash
# Uso: failover-test.sh <rótulo> [--one-side]     ex.: failover-test.sh ospf
# Roteamento já deve estar ativo. Ping host1->host3 a cada 200 ms por 40 s;
# em t=10 s derruba o enlace R2-R3; em t=30 s mostra o novo caminho; ao final restaura o enlace.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL=${1:?uso: $0 rótulo [--one-side]}; shift || true
DST=192.168.3.10
OUT="$DIR/../metrics/failover-$LABEL.txt"
mkdir -p "$DIR/../metrics"

echo "== caminho ANTES da falha"
podman exec host1 traceroute -n -q1 -w1 $DST

podman exec host1 ping -i 0.2 -D -O -c 200 $DST > "$OUT" 2>&1 &
PING=$!
sleep 10
echo "== derrubando enlace R2-R3"
"$DIR/fail-link.sh" r2 r3 "$@"
sleep 20
echo "== caminho DEPOIS da falha"
podman exec host1 traceroute -n -q1 -w1 $DST
wait $PING || true

"$DIR/restore-link.sh" r2 r3
tx=$(grep -oE '[0-9]+ packets transmitted' "$OUT" | grep -oE '^[0-9]+')
rx=$(grep -oE '[0-9]+ received' "$OUT" | grep -oE '^[0-9]+')
lost=$((tx - rx))
echo "== RESULTADO ($LABEL): $lost de $tx pacotes perdidos = ~$(awk "BEGIN{print $lost*0.2}") s sem conectividade"
echo "   log completo em metrics/failover-$LABEL.txt"
