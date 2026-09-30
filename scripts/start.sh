#!/usr/bin/env bash
# Sobe o laboratório: redes, imagens e 10 containers (5 roteadores + 5 hosts).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/stop.sh"
"$ROOT/scripts/create-networks.sh"

echo "construindo imagens (usa cache)..."
podman build -q -t localhost/routing-lab-router "$ROOT/routers" > /dev/null
podman build -q -t localhost/routing-lab-host   "$ROOT/hosts"   > /dev/null

# número  LAN:ip  enlace1:ip  enlace2:ip
ROUTERS=(
  "1 lan-r1:192.168.1.1 net-r1-r2:10.0.12.1 net-r5-r1:10.0.51.2"
  "2 lan-r2:192.168.2.1 net-r1-r2:10.0.12.2 net-r2-r3:10.0.23.1"
  "3 lan-r3:192.168.3.1 net-r2-r3:10.0.23.2 net-r3-r4:10.0.34.1"
  "4 lan-r4:192.168.4.1 net-r3-r4:10.0.34.2 net-r4-r5:10.0.45.1"
  "5 lan-r5:192.168.5.1 net-r4-r5:10.0.45.2 net-r5-r1:10.0.51.1"
)

for entry in "${ROUTERS[@]}"; do
  read -r n a b c <<< "$entry"
  podman run -d --name "router-r$n" --hostname "r$n" \
    --cap-add NET_ADMIN --cap-add NET_RAW \
    --sysctl net.ipv4.ip_forward=1 \
    --sysctl net.ipv4.conf.all.rp_filter=0 \
    --sysctl net.ipv4.conf.default.rp_filter=0 \
    -v "$ROOT/configs:/configs:ro,z" \
    --stop-timeout 1 \
    --network "${a/:/:ip=}" --network "${b/:/:ip=}" --network "${c/:/:ip=}" \
    localhost/routing-lab-router > /dev/null
  echo "router-r$n iniciado"
done

for n in 1 2 3 4 5; do
  podman run -d --name "host$n" --hostname "host$n" \
    --cap-add NET_ADMIN --cap-add NET_RAW \
    -e "GATEWAY=192.168.$n.1" \
    --stop-timeout 1 \
    --network "lan-r$n:ip=192.168.$n.10" \
    localhost/routing-lab-host > /dev/null
  echo "host$n iniciado"
done
