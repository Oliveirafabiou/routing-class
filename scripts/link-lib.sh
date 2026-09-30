# Funções comuns de manipulação de enlaces (usadas por fail-link.sh / restore-link.sh)
declare -A LINKIP=(
  ["r1 r2"]=10.0.12.1 ["r2 r1"]=10.0.12.2
  ["r2 r3"]=10.0.23.1 ["r3 r2"]=10.0.23.2
  ["r3 r4"]=10.0.34.1 ["r4 r3"]=10.0.34.2
  ["r4 r5"]=10.0.45.1 ["r5 r4"]=10.0.45.2
  ["r5 r1"]=10.0.51.1 ["r1 r5"]=10.0.51.2
)
# iface_of <roteador> <vizinho>: nome da interface do roteador voltada ao vizinho (achada pelo IP)
iface_of() {
  local ip=${LINKIP["$1 $2"]:-}
  [ -n "$ip" ] || { echo "enlace $1-$2 não existe" >&2; return 1; }
  local i
  i=$(podman exec "router-$1" ip -o -4 addr show | awk -v ip="$ip/" 'index($4, ip)==1 {sub(/@.*/, "", $2); print $2}')
  [ -n "$i" ] || { echo "interface de $1 para $2 não encontrada" >&2; return 1; }
  echo "$i"
}
