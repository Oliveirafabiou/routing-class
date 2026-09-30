#!/usr/bin/env bash
# Uso: test-connectivity.sh [basic|full]
#   basic: sem roteamento -> só vizinhos diretos respondem; LANs diferentes NÃO se alcançam.
#   full : com roteamento (static/rip/ospf) -> todos os hosts se alcançam.
MODE=${1:-basic}
pass=0; fail=0

t() {  # container destino esperado(ok|fail) descrição
  local c=$1 dst=$2 exp=$3 desc=$4 res=fail
  podman exec "$c" ping -c1 -W1 "$dst" > /dev/null 2>&1 && res=ok
  if [ "$res" = "$exp" ]; then echo "  PASS  $desc"; pass=$((pass+1))
  else echo "  FAIL  $desc (esperado: $exp, obtido: $res)"; fail=$((fail+1)); fi
}
norm() { tr ' ' '\n' | sort | xargs; }
nets() { podman inspect "$1" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' | norm; }

echo "== 1. Vizinhos diretos (enlaces /30)"
t router-r1 10.0.12.2 ok "R1 -> R2 (10.0.12.2)"
t router-r2 10.0.23.2 ok "R2 -> R3 (10.0.23.2)"
t router-r3 10.0.34.2 ok "R3 -> R4 (10.0.34.2)"
t router-r4 10.0.45.2 ok "R4 -> R5 (10.0.45.2)"
t router-r5 10.0.51.2 ok "R5 -> R1 (10.0.51.2)"
for n in 1 2 3 4 5; do
  t router-r$n 192.168.$n.10 ok "R$n -> host$n"
  t host$n 192.168.$n.1 ok "host$n -> gateway R$n"
done

echo "== 2. Isolamento: cada container só está nas suas redes"
declare -A EXP=(
  [router-r1]="lan-r1 net-r1-r2 net-r5-r1"
  [router-r2]="lan-r2 net-r1-r2 net-r2-r3"
  [router-r3]="lan-r3 net-r2-r3 net-r3-r4"
  [router-r4]="lan-r4 net-r3-r4 net-r4-r5"
  [router-r5]="lan-r5 net-r4-r5 net-r5-r1"
  [host1]="lan-r1" [host2]="lan-r2" [host3]="lan-r3" [host4]="lan-r4" [host5]="lan-r5"
)
for c in router-r{1..5} host{1..5}; do
  got=$(nets "$c"); want=$(echo "${EXP[$c]}" | norm)
  if [ "$got" = "$want" ]; then echo "  PASS  $c: $got"; pass=$((pass+1))
  else echo "  FAIL  $c: obtido [$got], esperado [$want]"; fail=$((fail+1)); fi
done
if [ "$MODE" = basic ]; then
  t router-r1 10.0.23.2 fail "R1 -/-> R3 (10.0.23.2): sem L2 direto e sem rota"
  t router-r1 10.0.34.1 fail "R1 -/-> R3 (10.0.34.1): sem L2 direto e sem rota"
  t router-r2 10.0.34.2 fail "R2 -/-> R4 (10.0.34.2): sem L2 direto e sem rota"
fi

echo "== 3. Fim a fim entre hosts (modo: $MODE)"
exp=fail; [ "$MODE" = full ] && exp=ok
for i in 1 2 3 4 5; do for j in 1 2 3 4 5; do
  [ "$i" != "$j" ] && t host$i 192.168.$j.10 $exp "host$i -> host$j"
done; done

echo; echo "Resultado: $pass PASS, $fail FAIL"
[ "$fail" -eq 0 ]
