#!/usr/bin/env bash
# Demonstração para o vídeo. Enter avança cada cena.
cd "$(dirname "$0")/.."
cena()  { echo; echo -e "\e[1;36m### $*\e[0m"; }
pausa() { read -rp "[Enter para continuar] " _; }
run()   { echo -e "\e[33m\$ $*\e[0m"; eval "$@"; }
espera(){ echo "aguardando convergência ($1 s)..."; sleep "$1"; }

cena "1. Ambiente: 5 roteadores, 5 hosts e 10 redes virtuais"
run "podman ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'NAMES|router|host'"
run "podman network ls --format '{{.Name}}' | grep -E '^(net|lan)-'"
pausa

cena "2. Isolamento: sem roteamento, o R1 não alcança a rede R2-R3"
run "./scripts/routing.sh stop"
run "podman inspect router-r1 --format '{{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}} {{end}}'"
run "podman exec router-r1 ping -c 2 -W 1 10.0.23.2"
pausa

demo() {  # modo  filtro-tcpdump  comando-vizinhos  comando-rotas
  cena "$1: ativar, conferir rotas, vizinhos e pacotes de controle"
  run "./scripts/routing.sh $1"
  espera 25
  run "$4"
  run "$3"
  run "podman exec host1 traceroute -n 192.168.3.10"
  run "podman exec router-r1 timeout 8 tcpdump -ni any -c 4 $2"
  pausa
  cena "$1: falha do enlace R2-R3 com ping contínuo host1 -> host3"
  run "./scripts/failover-test.sh demo-$1"
  pausa
}
demo rip   "udp port 520"  "./scripts/birdc.sh r1 show rip neighbors"  "./scripts/birdc.sh r1 show route"
demo ospf  "ip proto 89"   "./scripts/birdc.sh r1 show ospf neighbors" "./scripts/birdc.sh r1 show route"
demo rttls "udp port 5000" "podman exec router-r1 tail -5 /var/log/rttls.log" "podman exec router-r1 ip route show proto 99"

cena "6. Enlace lento: +30 ms de RTT no R2-R3"
run "./scripts/set-delay.sh r2 r3 15"
for m in rip ospf rttls; do
  echo -e "\n\e[1m-- $m\e[0m"
  ./scripts/routing.sh $m > /dev/null; espera 25
  run "podman exec host1 traceroute -n -q1 192.168.3.10"
  run "podman exec host1 ping -c 5 -q 192.168.3.10 | tail -1"
done
run "./scripts/clear-delay.sh r2 r3"
rm -f metrics/failover-demo-*.txt
cena "Fim. Código, configs, métricas e gráficos no GitHub."
run "git log --oneline | head -3"
