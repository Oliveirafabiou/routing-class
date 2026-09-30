FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bird2 iproute2 iputils-ping traceroute tcpdump procps python3 \
 && rm -rf /var/lib/apt/lists/*
# O BIRD e o RTT-LS NÃO iniciam aqui: scripts/routing.sh escolhe o modo.
CMD ["sleep", "infinity"]
