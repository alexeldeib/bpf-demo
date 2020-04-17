#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

TAG="$(date -Iseconds | tr :+ -)"
echo "TAG: ${TAG}"

sudo docker build -t ${REPO}/${IMAGE}:${TAG} .
sudo docker tag ${REPO}/${IMAGE}:${TAG} ${REPO}/${IMAGE}:latest
sudo docker push ${REPO}/${IMAGE}:${TAG}
sudo docker push ${REPO}/${IMAGE}:latest

docker images 

