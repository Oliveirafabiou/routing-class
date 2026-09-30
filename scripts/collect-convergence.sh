#!/usr/bin/env bash
# Uso: collect-convergence.sh [repeticoes=3]  -> metrics/convergencia.csv
# Cada repetição: reinicia o mecanismo, espera convergir, derruba R2-R3 (duas pontas) e conta perdas.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPS=${1:-3}
OUT="$ROOT/metrics/convergencia.csv"
echo "modo,repeticao,perdidos,total,tempo_s" > "$OUT"
for modo in rip ospf rttls; do
  for i in $(seq 1 "$REPS"); do
    "$ROOT/scripts/routing.sh" "$modo" > /dev/null
    sleep 30
    "$ROOT/scripts/failover-test.sh" "$modo-$i" > "$ROOT/metrics/failover-$modo-$i.log" 2>&1
    f="$ROOT/metrics/failover-$modo-$i.txt"
    tx=$(grep -oE '[0-9]+ packets transmitted' "$f" | grep -oE '^[0-9]+')
    rx=$(grep -oE '[0-9]+ received' "$f" | grep -oE '^[0-9]+')
    lost=$((tx - rx))
    echo "$modo,$i,$lost,$tx,$(awk "BEGIN{print $lost*0.2}")" | tee -a "$OUT"
  done
done
