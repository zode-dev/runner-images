#!/bin/sh
# debian-13: runs as root inside the guest on its first boot
# (scripts/build-base.sh). Packages come from Debian's own mirrors, with the
# security suite, so every rebuild carries the week's security updates.
set -eux
# shellcheck source=scripts/guest/common.sh
. /root/zode/common.sh
export DEBIAN_FRONTEND=noninteractive

retry apt-get update
retry apt-get -y -o Dpkg::Options::=--force-confold full-upgrade
retry apt-get install -y --no-install-recommends \
  ca-certificates curl wget gnupg git jq unzip zip xz-utils zstd ripgrep fd-find tree \
  build-essential pkg-config libssl-dev cmake binutils \
  python3 python3-pip python3-venv python3-dev pipx nodejs npm golang-go \
  sqlite3 iproute2 iputils-ping dnsutils netcat-openbsd openssh-client sudo \
  vim nano less tmux htop lsof strace cloud-guest-utils btrfs-progs \
  docker.io docker-cli docker-buildx docker-compose
# Browser and desktop (zode browser / zode desktop): Chromium, a virtual
# display, Xfce and what voxl links. Nothing runs until a sandbox asks.
retry apt-get install -y --no-install-recommends \
  chromium libnss3-tools \
  xvfb x11-xserver-utils dbus-x11 dbus-daemon libglib2.0-bin at-spi2-core \
  xfce4-session xfwm4 xfce4-panel xfdesktop4 xfce4-terminal thunar xfce4-settings \
  adwaita-icon-theme fonts-dejavu fonts-liberation fonts-noto-color-emoji \
  libx264-164 libyuv0 libopus0 libpulse0 pulseaudio
systemctl --global disable pulseaudio.service pulseaudio.socket 2>/dev/null || true

# Docker pulls go through the node's mirror first, like the Ubuntu base.
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<JSON
{ "registry-mirrors": ["$MIRROR"], "insecure-registries": ["172.16.0.1:5000"] }
JSON
systemctl enable docker

install_voxl
environment /usr/bin/chromium
apt-get clean
rm -rf /var/lib/apt/lists/*
finish
