#!/usr/bin/env bash
# Uso: restore-link.sh <ra> <rb>     ex.: restore-link.sh r2 r3
set -euo pipefail
source "$(dirname "$0")/link-lib.sh"
A=${1:?uso: $0 ra rb}; B=${2:?uso: $0 ra rb}
ia=$(iface_of "$A" "$B"); ib=$(iface_of "$B" "$A")
podman exec "router-$A" ip link set "$ia" up
podman exec "router-$B" ip link set "$ib" up
echo "$(date +%T.%N) enlace $A-$B restaurado ($ia / $ib)"
