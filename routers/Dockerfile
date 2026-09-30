FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bird2 iproute2 iputils-ping traceroute tcpdump procps \
 && rm -rf /var/lib/apt/lists/*
# O BIRD NÃO é iniciado aqui: os scripts iniciam com a config de cada experimento.
CMD ["sleep", "infinity"]
