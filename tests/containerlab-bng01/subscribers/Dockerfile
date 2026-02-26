# BNG Blaster subscriber simulator
#
# Builds bngblaster from source for any architecture (arm64/amd64).
# The official RTBrick releases only provide amd64 .deb packages.
FROM debian:bookworm-slim AS builder

ARG BNGBLASTER_VERSION=0.9.30
ARG LIBDICT_VERSION=1.0.5

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      git cmake make gcc g++ \
      libssl-dev libncurses-dev libjansson-dev libpcap-dev libcunit1-dev \
      ca-certificates

# Build libdict from source (no arm64 .deb available)
RUN git clone --depth 1 --branch ${LIBDICT_VERSION} \
      https://github.com/rtbrick/libdict.git /libdict && \
    mkdir /libdict/build && cd /libdict/build && \
    cmake .. && make -j"$(nproc)" && make install && \
    ldconfig

# Build bngblaster
RUN git clone --depth 1 --branch ${BNGBLASTER_VERSION} \
      https://github.com/rtbrick/bngblaster.git /src && \
    mkdir /src/build && cd /src/build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j"$(nproc)" && \
    make install

FROM debian:bookworm-slim

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      libssl3 libncurses6 libjansson4 libpcap0.8 iproute2 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/sbin/bngblaster /usr/sbin/bngblaster
COPY --from=builder /usr/local/lib/libdict* /usr/local/lib/
RUN ldconfig

CMD ["sleep", "infinity"]
