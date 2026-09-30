#!/bin/sh
# Configura o gateway padrão do host (variável GATEWAY) e mantém o container vivo.
ip route replace default via "$GATEWAY"
exec sleep infinity
