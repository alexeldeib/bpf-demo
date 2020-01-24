FROM golang:1.13.6-stretch as builder

RUN git clone https://github.com/cloudflare/ebpf_exporter /go/ebpf_exporter

RUN cd /go/ebpf_exporter && GOPATH="" GOPROXY="off" GOFLAGS="-mod=vendor" go install -v ./...

FROM ubuntu:disco

# Doing mostly what CI is doing here
RUN apt-get update 
RUN apt-get install -y apt-transport-https 
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 648A4A16A23015EEF4A66B8E4052245BD4284CDD 
RUN echo "deb https://repo.iovisor.org/apt/disco disco main" > /etc/apt/sources.list.d/iovisor.list 
RUN apt-get update 
RUN apt-get install -y linux-headers-amd64 apt-get install -y bcc-tools libbcc-examples libbpfcc-dev

COPY --from=builder /root/go/bin/ebpf_exporter /ebpf_exporter

ENTRYPOINT ["/ebpf_exporter"]