#!/usr/bin/env bash
# Uso: fail-link.sh <ra> <rb> [--one-side]     ex.: fail-link.sh r2 r3
# Simula FALHA DE ENLACE (o roteador continua ativo): desativa a interface que liga ra a rb.
set -euo pipefail
source "$(dirname "$0")/link-lib.sh"
A=${1:?uso: $0 ra rb [--one-side]}; B=${2:?uso: $0 ra rb [--one-side]}; ONE=${3:-}
ia=$(iface_of "$A" "$B"); ib=$(iface_of "$B" "$A")
podman exec "router-$A" ip link set "$ia" down
echo "$(date +%T.%N) router-$A: $ia DOWN"
if [ "$ONE" != "--one-side" ]; then
  podman exec "router-$B" ip link set "$ib" down
  echo "$(date +%T.%N) router-$B: $ib DOWN"
fi
