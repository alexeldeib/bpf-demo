REPO ?= docker.io/alexeldeib
TAG ?= latest

.PHONY: images/bpftrace
images/bpftrace:
	docker build -f images/bpftrace/Dockerfile -t ${REPO}/bpftrace:${TAG} .
	docker push ${REPO}/bpftrace:${TAG}

.PHONY: images/bpf_exporter
images/bpf_exporter:
	docker build -f images/bpf_exporter/Dockerfile -t ${REPO}/bpf_exporter:${TAG} .
	docker push ${REPO}/bpf_exporter:${TAG}

.PHONY: images
images: images/bpftrace images/bpf_exporter

