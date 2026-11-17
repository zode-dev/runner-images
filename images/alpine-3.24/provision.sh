#!/bin/sh
# alpine-3.24: runs as root inside the guest on its first boot
# (scripts/build-base.sh). musl and OpenRC: the agent is an OpenRC service
# (common.sh), eudev replaces mdev so the hotplug rules apply as they do
# everywhere else, and apk upgrade carries the week's security fixes.
set -eux
# shellcheck source=scripts/guest/common.sh
. /root/zode/common.sh

ensure_dns
# The cloud image ships the main repository only.
v=$(cut -d. -f1,2 /etc/alpine-release)
cat >/etc/apk/repositories <<REPOS
https://dl-cdn.alpinelinux.org/alpine/v$v/main
https://dl-cdn.alpinelinux.org/alpine/v$v/community
REPOS
retry apk update
retry apk upgrade --available
# The image's root is about 1 GB; grow it to the disk before the big installs.
retry apk add cloud-utils-growpart e2fsprogs-extra util-linux
hotplug
/usr/local/lib/zode/grow-root
df -h /
retry apk add \
  bash ca-certificates curl wget gnupg git jq unzip zip xz zstd ripgrep fd tree \
  build-base pkgconf openssl-dev cmake binutils coreutils findutils util-linux \
  python3 py3-pip pipx nodejs npm go \
  sqlite iproute2 iputils bind-tools netcat-openbsd openssh-client sudo shadow \
  vim nano less tmux htop lsof strace cloud-utils-growpart e2fsprogs-extra \
  docker docker-cli-buildx docker-cli-compose \
  chromium nss-tools eudev udev-init-scripts udev-init-scripts-openrc

# Hotplug rules need udev, not busybox mdev.
setup-devd udev

mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<JSON
{ "registry-mirrors": ["$MIRROR"], "insecure-registries": ["172.16.0.1:5000"] }
JSON
rc-update add docker default
rc-update add cgroups boot 2>/dev/null || true

environment /usr/bin/chromium
finish
