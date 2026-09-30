#!/usr/bin/env bash
# Uso: birdc.sh r1 show route   |   birdc.sh r3 show protocols
n=${1:?uso: $0 r1..r5 <comando birdc>}; shift
podman exec "router-$n" birdc -s /run/bird/bird.ctl "$@"
