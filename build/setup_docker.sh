#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# systemd drop-in for docker networking
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo cp ~/bpf-demo/build/10-docker-net.conf /etc/systemd/system/docker.service.d/10-docker-net.conf

## gpg key
curl -fsSl https://download.docker.com/linux/ubuntu/gpg -o gpg.asc
sudo apt-key add gpg.asc

# apt repo
DISTRO="$(cat /etc/os-release | grep ^ID= | cut -d= -f2)"
CODENAME="$(cat /etc/os-release | grep VERSION_CODENAME= | cut -d= -f2)"
echo "deb [arch=amd64] https://download.docker.com/linux/${DISTRO} ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list

# install docker
sudo apt update && sudo apt install -y docker-ce

# login
cat ~/.docker_pass | sudo docker login -u "$(cat ~/.docker_user)" --password-stdin
