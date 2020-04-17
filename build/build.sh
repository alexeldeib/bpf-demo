#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

cd "~/${APP}/images/bpftrace"
TAG="$(date -Iseconds | tr :+ -)"
echo "TAG: ${TAG}"
sudo docker build -t ${REPO}/${APP}:${TAG} .
sudo docker tag ${REPO}/${APP}:${TAG} ${REPO}/${APP}:latest
sudo docker push ${REPO}/${APP}:${TAG}
sudo docker push ${REPO}/${APP}:latest
docker images
