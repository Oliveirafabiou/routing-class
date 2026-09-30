#!/usr/bin/env bash
# Uso: collect-metrics.sh <rip|ospf|rttls> [duracao_regime_s=60]
# Mede: pacotes/bytes de controle (convergência inicial e regime), tamanho da tabela e delay.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=${1:?uso: $0 rip|ospf|rttls [duracao_s]}; DUR=${2:-60}
case $MODE in
  rip)   FILTER='udp port 520' ;;
  ospf)  FILTER='ip proto 89' ;;
  rttls) FILTER='udp port 5000' ;;
  *) echo "modo inválido: $MODE"; exit 1 ;;
esac
RAW="$ROOT/metrics/raw/$MODE"; mkdir -p "$RAW"

"$ROOT/scripts/routing.sh" stop > /dev/null
for n in 1 2 3 4 5; do   # captura só pacotes ENVIADOS pelo roteador
  podman exec router-r$n rm -f /tmp/cap.pcap
  podman exec -d router-r$n sh -c "exec timeout $((DUR+32)) tcpdump -i any -Q out -nn -U -w /tmp/cap.pcap $FILTER"
done
sleep 2
T0=$(date +%s.%N)
"$ROOT/scripts/routing.sh" "$MODE"
echo "coletando: 30 s de convergência inicial + $DUR s em regime..."
sleep $((DUR+34))

# tamanho da tabela de roteamento (todas as rotas do kernel, por roteador)
TAB="$ROOT/metrics/tabela.csv"
[ -f "$TAB" ] || echo "modo,roteador,rotas" > "$TAB"
sed -i "/^$MODE,/d" "$TAB"
for n in 1 2 3 4 5; do
  echo "$MODE,r$n,$(podman exec router-r$n ip -o route | wc -l)" >> "$TAB"
done

for n in 1 2 3 4 5; do podman cp router-r$n:/tmp/cap.pcap "$RAW/r$n.pcap" > /dev/null; done
python3 "$ROOT/scripts/parse-pcap.py" "$MODE" "$T0" "$DUR"

# delay fim a fim (20 pings)
DEL="$ROOT/metrics/delay.csv"
[ -f "$DEL" ] || echo "modo,par,rtt_medio_ms" > "$DEL"
sed -i "/^$MODE,/d" "$DEL"
for par in "1 3" "1 4"; do
  read -r a b <<< "$par"
  avg=$(podman exec host$a ping -c 20 -i 0.2 -q 192.168.$b.10 | awk -F/ '/^rtt/ {print $5}')
  echo "$MODE,host$a-host$b,$avg" >> "$DEL"
done
echo "OK: $MODE"
