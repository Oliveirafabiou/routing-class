#!/usr/bin/env bash
# Uso: clear-delay.sh <ra> <rb>
set -euo pipefail
source "$(dirname "$0")/link-lib.sh"
A=$1; B=$2
podman exec "router-$A" tc qdisc del dev "$(iface_of "$A" "$B")" root 2>/dev/null || true
podman exec "router-$B" tc qdisc del dev "$(iface_of "$B" "$A")" root 2>/dev/null || true
echo "enlace $A-$B: delay removido"
