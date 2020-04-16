
FROM ubuntu:20.04

RUN apt update -y
RUN apt-get install -y git \
 jq \
 bpfcc-tools \
 bpftrace \
 magic-wormhole \
 sysstat

RUN git clone https://github.com/brendangregg/FlameGraph /flamegraph && chmod +x /flamegraph/*.pl
RUN git clone https://github.com/brendangregg/HeatMap /heatmap && chmod +x /heatmap/*.pl
ENV PATH "$PATH:/heatmap:/flamegraph"
