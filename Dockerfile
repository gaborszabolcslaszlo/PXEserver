FROM ubuntu:24.04

ARG IVENTOY_VERSION=1.0.42

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        tar \
        bash \
        procps \
        iproute2 \
        net-tools \
        libc6 \
        libstdc++6 \
        libgcc-s1 \
        zlib1g \
        libglib2.0-0 \
        libx11-6 \
        libxext6 \
        libxrender1 \
        libxrandr2 \
        libxfixes3 \
        libxi6 \
        libxtst6 \
        libnss3 \
        libgtk-3-0 \
        && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /iventoy

RUN wget -O /tmp/iventoy.tar.gz \
    "https://github.com/ventoy/PXE/releases/download/v${IVENTOY_VERSION}/iventoy-${IVENTOY_VERSION}-linux-x86_64-free.tar.gz" \
    && \
    tar -xzf /tmp/iventoy.tar.gz --strip-components=1 \
    && \
    rm /tmp/iventoy.tar.gz

RUN chmod +x /iventoy/iventoy.sh

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 26000/tcp
EXPOSE 16000/tcp
EXPOSE 69/udp
EXPOSE 67/udp
EXPOSE 4011/udp
EXPOSE 10809/tcp

ENTRYPOINT ["/entrypoint.sh"]
