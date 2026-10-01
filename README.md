# routing-lab

Laboratório de roteamento IP com Podman e BIRD (Fundamentos de Sistemas Operacionais, Unisinos).
Compara **RIP**, **OSPF** e um algoritmo próprio, o **RTT-LS**, sobre a mesma topologia. Só um mecanismo roda por vez.

## Topologia

Anel de 5 roteadores. Cada enlace é uma rede /30 independente e cada roteador tem uma LAN /24 com um host.

```text
                 LAN1 192.168.1.0/24 ── host1
                          │
                         [R1]
          10.0.51.0/30 ╱      ╲ 10.0.12.0/30
 host5 ─ LAN5 ─ [R5]              [R2] ─ LAN2 ─ host2
 192.168.5.0/24   │                 │    192.168.2.0/24
         10.0.45.0/30          10.0.23.0/30
                  │                 │
 host4 ─ LAN4 ─ [R4] ──────────── [R3] ─ LAN3 ─ host3
 192.168.4.0/24      10.0.34.0/30        192.168.3.0/24
```

| Roteador | LAN (roteador / host) | Enlaces |
|---|---|---|
| R1 | 192.168.1.1 / .10 | 10.0.12.1 (R2), 10.0.51.2 (R5) |
| R2 | 192.168.2.1 / .10 | 10.0.12.2 (R1), 10.0.23.1 (R3) |
| R3 | 192.168.3.1 / .10 | 10.0.23.2 (R2), 10.0.34.1 (R4) |
| R4 | 192.168.4.1 / .10 | 10.0.34.2 (R3), 10.0.45.1 (R5) |
| R5 | 192.168.5.1 / .10 | 10.0.45.2 (R4), 10.0.51.1 (R1) |

São 10 containers (`router-r1..5`, `host1..5`) e 10 redes Podman internas (`net-r1-r2`, `net-r2-r3`, `net-r3-r4`, `net-r4-r5`, `net-r5-r1`, `lan-r1..5`). Nenhum roteador compartilha rede com quem não é seu vizinho.

## Requisitos

Podman (testado rootless, 5.8, backend netavark), Python 3 e matplotlib no host (`pip install --user matplotlib`). BIRD 2.0, tcpdump e traceroute ficam nas imagens dos containers.

## Uso

```bash
./scripts/start.sh                    # cria redes, imagens e os 10 containers
./scripts/routing.sh <static|rip|ospf|rttls|stop>   # ativa UM mecanismo (para o anterior)
./scripts/test-connectivity.sh basic  # sem roteamento: prova o isolamento
./scripts/test-connectivity.sh full   # com roteamento: todos os hosts se alcançam
./scripts/birdc.sh r1 show route      # consultar o BIRD (rip/ospf/static)
podman exec router-r1 ip route show proto 99   # rotas do RTT-LS
./scripts/stop.sh [--networks]        # remove containers (e, opcionalmente, as redes)
```

Captura de pacotes de roteamento: `podman exec router-r1 tcpdump -ni any udp port 520` (RIP), `ip proto 89` (OSPF), `udp port 5000` (RTT-LS).

### Falha de enlace e enlace lento

```bash
./scripts/fail-link.sh r2 r3 [--one-side]   # derruba só a interface (o roteador continua ativo)
./scripts/restore-link.sh r2 r3
./scripts/failover-test.sh <rótulo>         # ping host1->host3, derruba R2-R3, mede perdas
./scripts/set-delay.sh r2 r3 15             # +15 ms por sentido (netem); clear-delay.sh remove
```

### Métricas e gráficos

```bash
for m in rip ospf rttls; do ./scripts/collect-metrics.sh $m; done   # tabela, controle, delay
./scripts/collect-slowlink.sh            # cenário do enlace lento
./scripts/collect-convergence.sh 3       # convergência, 3 repetições por mecanismo
python3 scripts/plot-metrics.py          # gráficos em metrics/graficos/ e metrics/resumo.md
```

## Mecanismos

- **Estático:** apenas para validar a topologia (`configs/static`).
- **RIP:** RIPv2, update 5 s, timeout 20 s (`configs/rip`).
- **OSPF:** área 0, enlaces ptp, hello 2 s, dead 8 s (`configs/ospf`).
- **RTT-LS** (`configs/rttls/rttls.py`): estado de enlace distribuído em Python, UDP/5000. Cada roteador mede o RTT dos vizinhos (1 por segundo, média móvel α = 0,3), usa o custo `1 + RTT(ms)`, inunda os anúncios, roda Dijkstra e instala rotas com `ip route ... proto 99`. Desempate pelo menor id do próximo salto, reanúncio só se o custo mudar mais de 25%, vizinho caído após 3 s sem resposta ou erro de envio.

## Resultados (resumo)

| Mecanismo | Controle em regime (pkt/s, rede toda) | bit/s | Convergência após falha R2-R3 | RTT com R2-R3 lento |
|---|---|---|---|---|
| RIP | 3,0 | 5.506 | 4,4 s | 30,05 ms |
| OSPF | 7,2 | 3.867 | 1,4 s | 30,04 ms |
| RTT-LS | 22,4 | 13.091 | 0,8 s | 0,024 ms |

Os dados brutos estão em `metrics/*.csv`. A convergência tem resolução de 0,2 s e foi medida derrubando as duas pontas do enlace.

## Vídeo

https://youtu.be/wrGjtrA-Q3A

## Estrutura

`routers/` e `hosts/` (imagens), `configs/` (static, rip, ospf, rttls), `scripts/`, `metrics/` (CSVs, capturas e gráficos).
