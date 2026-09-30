#!/usr/bin/env bash
# Cenário do enlace lento: +15 ms por sentido em R2-R3 (RTT +30 ms). Grava metrics/slowlink.csv
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/metrics/slowlink.csv"
echo "modo,caminho,rtt_medio_ms" > "$OUT"
"$ROOT/scripts/set-delay.sh" r2 r3 15
trap '"$ROOT/scripts/clear-delay.sh" r2 r3' EXIT
for modo in rip ospf rttls; do
  "$ROOT/scripts/routing.sh" "$modo" > /dev/null
  sleep 25
  hop2=$(podman exec host1 traceroute -n -q1 192.168.3.10 | awk 'NR==3 {print $2}')
  if [ "$hop2" = "10.0.12.2" ]; then via="R1-R2-R3"; else via="R1-R5-R4-R3"; fi
  avg=$(podman exec host1 ping -c 20 -i 0.2 -q 192.168.3.10 | awk -F/ '/^rtt/ {print $5}')
  echo "$modo,$via,$avg" | tee -a "$OUT"
done
