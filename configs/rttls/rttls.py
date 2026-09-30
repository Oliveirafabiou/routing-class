#!/usr/bin/env python3
"""RTT-LS: roteamento por estado de enlace com custo = 1 + RTT medido (ms).
Um daemon por roteador. Mensagens JSON sobre UDP/5000, unicast entre vizinhos diretos."""
import heapq, ipaddress, json, re, select, signal, socket, subprocess, sys, time

PORT, HELLO, DEAD, REFRESH, MAXAGE, ALPHA = 5000, 1.0, 3.0, 10.0, 30.0, 0.3
PROTO = "99"  # marca das rotas instaladas por este daemon

def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)

def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

class RttLs:
    def __init__(self):
        self.me = int(re.sub(r"\D", "", socket.gethostname()))   # hostname "r1" -> 1
        self.nets, self.nb = [], {}
        for line in run("ip", "-o", "-4", "addr", "show").stdout.splitlines():
            m = re.match(r"\d+:\s+(\S+?)(?:@\S+)?\s+inet\s+(\S+)", line)
            if not m or m.group(1) == "lo":
                continue
            ifc = ipaddress.ip_interface(m.group(2))
            self.nets.append(str(ifc.network))
            if ifc.network.prefixlen == 30:      # enlace entre roteadores
                peer = [h for h in ifc.network.hosts() if h != ifc.ip][0]
                self.nb[str(peer)] = dict(iface=m.group(1), id=None, up=False, rx=0.0, rtt=None)
        self.lsdb, self.installed, self.adv = {}, {}, {}
        self.seq, self.dirty = int(time.time()), False
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", PORT))
        run("ip", "route", "flush", "proto", PROTO)
        log(f"R{self.me} iniciado; redes {self.nets}; vizinhos {list(self.nb)}")
        self.originate(force=True)

    # ---------- envio ----------
    def send(self, ip, msg):
        try:
            self.sock.sendto(json.dumps(msg, separators=(",", ":")).encode(), (ip, PORT))
            return True
        except OSError:
            return False

    def flood(self, msg, skip=None):
        for ip, n in self.nb.items():
            if n["up"] and ip != skip:
                self.send(ip, msg)

    def hello(self):
        now = time.monotonic()
        for ip, n in self.nb.items():
            if not self.send(ip, {"t": "p", "f": self.me, "ts": now}) and n["up"]:
                self.down(ip, "erro de envio (interface/rota indisponível)")

    # ---------- vizinhos ----------
    def forget_routes(self, iface):
        for p in [p for p, (_, i) in self.installed.items() if i == iface]:
            del self.installed[p]

    def down(self, ip, why):
        n = self.nb[ip]
        n["up"], n["rtt"] = False, None
        log(f"vizinho R{n['id']} ({ip}, {n['iface']}) DOWN: {why}")
        self.originate(force=True)

    def up(self, ip, n, rid):
        n["up"], n["id"] = True, rid
        self.forget_routes(n["iface"])
        log(f"vizinho R{rid} ({ip}, {n['iface']}) UP, rtt={n['rtt']:.2f} ms")
        self.originate(force=True)
        for o, l in self.lsdb.items():          # sincroniza a base com o vizinho que voltou
            if o != self.me:
                self.send(ip, l["msg"])

    def on_pong(self, ip, m):
        n = self.nb.get(ip)
        if not n:
            return
        now = time.monotonic()
        rtt = (now - m["ts"]) * 1000.0
        n["rx"] = now
        n["rtt"] = rtt if n["rtt"] is None else (1 - ALPHA) * n["rtt"] + ALPHA * rtt
        if not n["up"] or n["id"] != m["f"]:
            self.up(ip, n, m["f"])
        else:
            self.originate()

    # ---------- anúncios (LSA) ----------
    def originate(self, force=False):
        cur = {str(n["id"]): round(1.0 + n["rtt"], 1) for n in self.nb.values()
               if n["up"] and n["id"] is not None and n["rtt"] is not None}
        if not force:
            same = cur.keys() == self.adv.keys() and all(
                abs(cur[k] - self.adv[k]) <= max(1.0, 0.25 * self.adv[k]) for k in cur)
            if same:
                return
        self.seq += 1
        m = {"t": "l", "o": self.me, "s": self.seq, "nets": self.nets, "links": cur}
        self.adv = dict(cur)
        self.lsdb[self.me] = {"msg": m, "t": time.monotonic()}
        self.flood(m)
        self.dirty = True

    def on_lsa(self, src, m):
        o = m["o"]
        if o == self.me:
            return
        cur = self.lsdb.get(o)
        if cur and cur["msg"]["s"] >= m["s"]:
            return
        self.lsdb[o] = {"msg": m, "t": time.monotonic()}
        self.flood(m, skip=src)
        self.dirty = True

    # ---------- SPF e instalação de rotas ----------
    def spf(self):
        self.dirty = False
        db = {o: l["msg"] for o, l in self.lsdb.items()}
        if self.me not in db:
            return
        best = {self.me: (0.0, 0)}                      # nó -> (custo, primeiro salto)
        pq = [(0.0, 0, self.me)]
        while pq:
            d, fh, u = heapq.heappop(pq)
            if best.get(u) != (d, fh):
                continue
            for v, c in db[u]["links"].items():
                v = int(v)
                if v not in db or str(u) not in db[v]["links"]:   # exige enlace bidirecional
                    continue
                key = (round(d + c, 3), v if u == self.me else fh)
                if v not in best or key < best[v]:
                    best[v] = key
                    heapq.heappush(pq, (key[0], key[1], v))
        want = {}                                        # prefixo -> (melhor (custo, salto), origem)
        for o, m in db.items():
            if o == self.me or o not in best:
                continue
            for p in m["nets"]:
                if p not in self.nets and (p not in want or best[o] < want[p][0]):
                    want[p] = (best[o], o)
        routes = {}
        for p, ((cost, fh), o) in want.items():
            nip = next((ip for ip, n in self.nb.items() if n["up"] and n["id"] == fh), None)
            if nip:
                routes[p] = (nip, self.nb[nip]["iface"])
        changed = 0
        for p, r in routes.items():
            if self.installed.get(p) != r:
                res = run("ip", "route", "replace", p, "via", r[0], "dev", r[1], "proto", PROTO)
                if res.returncode:
                    log("erro ao instalar", p, res.stderr.strip())
                else:
                    self.installed[p] = r
                    changed += 1
        for p in [p for p in self.installed if p not in routes]:
            run("ip", "route", "del", p, "proto", PROTO)
            del self.installed[p]
            changed += 1
        if changed:
            log(f"SPF: {changed} mudança(s); {len(routes)} rotas ativas")

    # ---------- laço principal ----------
    def loop(self):
        nxt_hello, nxt_refresh = 0.0, time.monotonic() + REFRESH
        while True:
            now = time.monotonic()
            if now >= nxt_hello:
                self.hello()
                nxt_hello = now + HELLO
            for ip, n in self.nb.items():
                if n["up"] and now - n["rx"] > DEAD:
                    self.down(ip, "sem resposta (dead interval)")
            if now >= nxt_refresh:
                self.originate(force=True)
                for o in [o for o, l in self.lsdb.items() if o != self.me and now - l["t"] > MAXAGE]:
                    del self.lsdb[o]
                    self.dirty = True
                nxt_refresh = now + REFRESH
            if self.dirty:
                self.spf()
            r, _, _ = select.select([self.sock], [], [], 0.05)
            if r:
                data, (src, _) = self.sock.recvfrom(65535)
                try:
                    m = json.loads(data)
                except ValueError:
                    continue
                t = m.get("t")
                if t == "p":
                    self.send(src, {"t": "o", "f": self.me, "ts": m["ts"]})
                elif t == "o":
                    self.on_pong(src, m)
                elif t == "l":
                    self.on_lsa(src, m)

def main():
    d = RttLs()
    def bye(*_):
        run("ip", "route", "flush", "proto", PROTO)
        log("encerrado; rotas removidas")
        sys.exit(0)
    signal.signal(signal.SIGTERM, bye)
    signal.signal(signal.SIGINT, bye)
    d.loop()

if __name__ == "__main__":
    main()
