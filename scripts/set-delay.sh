#!/usr/bin/env bash
# Uso: set-delay.sh <ra> <rb> <ms por sentido>   ex.: set-delay.sh r2 r3 15  (RTT do enlace +30 ms)
set -euo pipefail
source "$(dirname "$0")/link-lib.sh"
A=$1; B=$2; MS=$3
podman exec "router-$A" tc qdisc replace dev "$(iface_of "$A" "$B")" root netem delay "${MS}ms"
podman exec "router-$B" tc qdisc replace dev "$(iface_of "$B" "$A")" root netem delay "${MS}ms"
echo "enlace $A-$B: +${MS} ms em cada sentido (RTT +$((2*MS)) ms)"
