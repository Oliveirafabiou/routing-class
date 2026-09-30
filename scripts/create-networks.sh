#!/usr/bin/env bash
# Cria as 10 redes do laboratório: 5 enlaces /30 entre roteadores e 5 LANs /24.
set -euo pipefail

NETWORKS=(
  "net-r1-r2 10.0.12.0/30"
  "net-r2-r3 10.0.23.0/30"
  "net-r3-r4 10.0.34.0/30"
  "net-r4-r5 10.0.45.0/30"
  "net-r5-r1 10.0.51.0/30"
  "lan-r1 192.168.1.0/24"
  "lan-r2 192.168.2.0/24"
  "lan-r3 192.168.3.0/24"
  "lan-r4 192.168.4.0/24"
  "lan-r5 192.168.5.0/24"
)

for entry in "${NETWORKS[@]}"; do
  read -r name subnet <<< "$entry"
  if podman network exists "$name"; then
    echo "já existe: $name"
  else
    podman network create --internal --disable-dns --subnet "$subnet" "$name" > /dev/null
    echo "criada:    $name ($subnet)"
  fi
done
