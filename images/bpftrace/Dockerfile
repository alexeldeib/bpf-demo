
FROM ubuntu:20.04

RUN apt update -y
RUN apt-get install -y git \
 jq \
 bpfcc-tools \
 bpftrace \
 magic-wormhole
RUN git clone https://github.com/brendangregg/FlameGraph.git /flamegraph
