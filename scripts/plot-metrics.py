#!/usr/bin/env python3
"""Gera os gráficos comparativos a partir dos CSVs em metrics/.
Saída: metrics/graficos/*.png e metrics/resumo.md"""
import csv, os, statistics as st
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M = os.path.join(ROOT, "metrics")
OUT = os.path.join(M, "graficos")
os.makedirs(OUT, exist_ok=True)

MODOS = ["rip", "ospf", "rttls"]
NOME = {"rip": "RIP", "ospf": "OSPF", "rttls": "RTT-LS"}
COR = {"rip": "#4C72B0", "ospf": "#DD8452", "rttls": "#55A868"}

def ler(nome):
    with open(os.path.join(M, nome), newline="") as f:
        return list(csv.DictReader(f))

def rotular(ax, barras, fmt="{:.1f}"):
    for b in barras:
        h = b.get_height()
        ax.annotate(fmt.format(h), (b.get_x() + b.get_width() / 2, h), ha="center",
                    va="bottom", fontsize=9, xytext=(0, 2), textcoords="offset points")

def grupos(ax, categorias, serie, fmt):
    w = 0.26
    for i, m in enumerate(MODOS):
        xs = [k + (i - 1) * w for k in range(len(categorias))]
        rotular(ax, ax.bar(xs, serie[m], w, label=NOME[m], color=COR[m]), fmt)
    ax.set_xticks(range(len(categorias)))
    ax.set_xticklabels(categorias)

def salvar(fig, nome):
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, nome), dpi=150)
    plt.close(fig)
    print("gerado:", nome)

def agregar_controle():
    acc = defaultdict(lambda: [0, 0, 0.0])   # pacotes, bytes, duração
    for r in ler("controle.csv"):
        k = (r["modo"], r["fase"])
        acc[k][0] += int(r["pacotes"])
        acc[k][1] += int(r["bytes_ip"])
        acc[k][2] = float(r["duracao_s"])
    return acc

def g_tabela():
    d = {(r["modo"], r["roteador"]): int(r["rotas"]) for r in ler("tabela.csv")}
    rot = [f"r{i}" for i in range(1, 6)]
    fig, ax = plt.subplots(figsize=(8, 4.5))
    grupos(ax, [r.upper() for r in rot], {m: [d.get((m, r), 0) for r in rot] for m in MODOS}, "{:.0f}")
    ax.set_ylabel("rotas na tabela do kernel")
    ax.set_title("Tamanho da tabela de roteamento por roteador")
    ax.set_ylim(0, max(d.values()) * 1.25)
    ax.legend()
    salvar(fig, "01_tabela.png")

FASES = [("inicial", "Convergência inicial"), ("estavel", "Regime estável")]

def g_controle(acc, conv, ylabel, titulo, arq):
    fig, ax = plt.subplots(figsize=(8, 4.5))
    grupos(ax, [n for _, n in FASES],
           {m: [conv(*acc[(m, f)]) for f, _ in FASES] for m in MODOS}, "{:.1f}")
    ax.set_ylabel(ylabel)
    ax.set_title(titulo)
    ax.set_ylim(0, ax.get_ylim()[1] * 1.12)
    ax.legend()
    salvar(fig, arq)

def g_delay():
    rows = ler("delay.csv")
    pares = sorted({r["par"] for r in rows})
    dd = {(r["modo"], r["par"]): float(r["rtt_medio_ms"]) for r in rows}
    slow = ler("slowlink.csv")
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(11, 4.5))
    grupos(a1, pares, {m: [dd.get((m, p), 0) for p in pares] for m in MODOS}, "{:.3f}")
    a1.set_ylabel("RTT médio (ms)")
    a1.set_title("Delay fim a fim (topologia normal)")
    a1.set_ylim(0, a1.get_ylim()[1] * 1.15)
    a1.legend()
    bars = a2.bar([f"{NOME[r['modo']]}\n{r['caminho']}" for r in slow],
                  [float(r["rtt_medio_ms"]) for r in slow], color=[COR[r["modo"]] for r in slow])
    rotular(a2, bars, "{:.2f}")
    a2.set_yscale("log")
    a2.set_ylim(0.01, max(float(r["rtt_medio_ms"]) for r in slow) * 4)
    a2.set_ylabel("RTT médio (ms, escala log)")
    a2.set_title("Enlace R2-R3 com +30 ms de RTT")
    salvar(fig, "04_delay.png")

def tempos_conv():
    conv = defaultdict(list)
    for r in ler("convergencia.csv"):
        conv[r["modo"]].append(float(r["tempo_s"]))
    return conv

def g_convergencia():
    conv = tempos_conv()
    fig, ax = plt.subplots(figsize=(7, 4.5))
    bars = ax.bar([NOME[m] for m in MODOS], [st.mean(conv[m]) for m in MODOS],
                  color=[COR[m] for m in MODOS], alpha=0.85)
    rotular(ax, bars, "{:.1f} s")
    for i, m in enumerate(MODOS):
        ax.scatter([i] * len(conv[m]), conv[m], color="black", zorder=3, s=18,
                   label="cada repetição" if i == 0 else None)
    ax.set_ylabel("tempo sem conectividade (s)")
    ax.set_xlabel("resolução da medição: 0,2 s (ping a cada 200 ms)")
    ax.set_title("Reconvergência após falha do enlace R2-R3")
    ax.set_ylim(0, ax.get_ylim()[1] * 1.15)
    ax.legend()
    salvar(fig, "05_convergencia.png")

def resumo(acc):
    tab = defaultdict(list)
    for r in ler("tabela.csv"):
        tab[r["modo"]].append(int(r["rotas"]))
    conv = tempos_conv()
    slow = {r["modo"]: (r["caminho"], float(r["rtt_medio_ms"])) for r in ler("slowlink.csv")}
    L = ["| Mecanismo | Rotas/roteador | Pacotes/s (regime) | bit/s (regime) | Pacotes/s (inicial) | Convergência média (s) | RTT com enlace lento (ms) |",
         "|---|---|---|---|---|---|---|"]
    for m in MODOS:
        pe, be, de = acc[(m, "estavel")]
        pi, _, di = acc[(m, "inicial")]
        L.append(f"| {NOME[m]} | {st.mean(tab[m]):.0f} | {pe / de:.1f} | {be * 8 / de:.0f} | "
                 f"{pi / di:.1f} | {st.mean(conv[m]):.1f} | {slow[m][1]:.2f} ({slow[m][0]}) |")
    txt = "\n".join(L) + "\n"
    with open(os.path.join(M, "resumo.md"), "w") as f:
        f.write(txt)
    print("\n" + txt)

def tentar(nome, fn):
    try:
        fn()
    except (FileNotFoundError, KeyError, ZeroDivisionError, ValueError) as e:
        print(f"PULADO {nome}: {type(e).__name__}: {e}")

acc = agregar_controle() if os.path.exists(os.path.join(M, "controle.csv")) else {}
tentar("tabela", g_tabela)
tentar("pacotes", lambda: g_controle(acc, lambda p, b, d: p / d, "pacotes de controle por segundo (rede toda)",
                                      "Pacotes de roteamento enviados", "02_pacotes_controle.png"))
tentar("taxa", lambda: g_controle(acc, lambda p, b, d: b * 8 / d, "bits por segundo (rede toda)",
                                   "Taxa de transmissão do tráfego de controle", "03_taxa_controle.png"))
tentar("delay", g_delay)
tentar("convergencia", g_convergencia)
tentar("resumo", lambda: resumo(acc))
