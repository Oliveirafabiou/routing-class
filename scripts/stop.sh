#!/usr/bin/env bash
# Remove os 10 containers. Com --networks, remove também as 10 redes.
set -uo pipefail

for c in router-r{1..5} host{1..5}; do
  podman rm -f -t 0 "$c" > /dev/null 2>&1 || true
done
echo "containers removidos"

if [ "${1:-}" = "--networks" ]; then
  for n in net-r1-r2 net-r2-r3 net-r3-r4 net-r4-r5 net-r5-r1 lan-r{1..5}; do
    podman network rm "$n" > /dev/null 2>&1 || true
  done
  echo "redes removidas"
fi
