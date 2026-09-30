#!/usr/bin/env python3
"""Uso: parse-pcap.py <modo> <t0> <duracao_regime>
Conta pacotes e bytes IP de controle por roteador, em duas fases, e grava em metrics/controle.csv."""
import os, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HDR = {276: 20, 113: 16, 1: 14, 101: 0}   # tamanho do cabeçalho de enlace por linktype

def packets(path):
    with open(path, "rb") as f:
        gh = f.read(24)
        if len(gh) < 24:
            return
        m = gh[:4]
        if m == b"\xd4\xc3\xb2\xa1":   e, div = "<", 1e6
        elif m == b"\x4d\x3c\xb2\xa1": e, div = "<", 1e9
        elif m == b"\xa1\xb2\xc3\xd4": e, div = ">", 1e6
        elif m == b"\xa1\xb2\x3c\x4d": e, div = ">", 1e9
        else: raise ValueError("pcap inválido: " + path)
        off = HDR[struct.unpack(e + "I", gh[20:24])[0]]
        while True:
            ph = f.read(16)
            if len(ph) < 16:
                break
            s, us, incl, _ = struct.unpack(e + "IIII", ph)
            data = f.read(incl)
            ip = data[off:]
            if len(ip) < 20 or ip[0] >> 4 != 4:
                continue
            yield s + us / div, struct.unpack(">H", ip[2:4])[0]

def main():
    modo, t0, dur = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    fases = {"inicial": (t0, t0 + 30), "estavel": (t0 + 30, t0 + 30 + dur)}
    rows, tot = [], {f: [0, 0] for f in fases}
    for n in range(1, 6):
        cnt = {f: [0, 0] for f in fases}
        for ts, ln in packets(f"{ROOT}/metrics/raw/{modo}/r{n}.pcap"):
            for f, (a, b) in fases.items():
                if a <= ts < b:
                    cnt[f][0] += 1
                    cnt[f][1] += ln
        for f, (a, b) in fases.items():
            rows.append(f"{modo},{f},r{n},{b - a:g},{cnt[f][0]},{cnt[f][1]}")
            tot[f][0] += cnt[f][0]
            tot[f][1] += cnt[f][1]
    out = f"{ROOT}/metrics/controle.csv"
    head = "modo,fase,router,duracao_s,pacotes,bytes_ip"
    old = []
    if os.path.exists(out):
        old = [l.rstrip("\n") for l in open(out) if l.strip() and not l.startswith(("modo,", modo + ","))]
    with open(out, "w") as fh:
        fh.write("\n".join([head] + old + rows) + "\n")
    for f, (a, b) in fases.items():
        p, by = tot[f]
        print(f"{modo} [{f}] rede toda: {p} pacotes, {by} bytes em {b - a:g} s = "
              f"{p / (b - a):.1f} pkt/s, {by * 8 / (b - a):.0f} bit/s")

main()
