#!/bin/sh
# arch: runs as root inside the guest on its first boot (scripts/build-base.sh).
# A full -Syu on every build; the reboot that follows runs the new kernel,
# so its modules (virtio_mem, overlay for Docker) are the ones on disk.
set -eux
# shellcheck source=scripts/guest/common.sh
. /root/zode/common.sh

pacman-key --init
pacman-key --populate archlinux
retry pacman -Sy --noconfirm --needed archlinux-keyring
retry pacman -Syu --noconfirm
retry pacman -S --noconfirm --needed \
  ca-certificates curl wget gnupg git jq unzip zip xz zstd ripgrep fd tree \
  base-devel pkgconf openssl cmake binutils \
  python python-pip python-pipx nodejs npm go \
  sqlite iproute2 iputils inetutils bind openbsd-netcat openssh sudo \
  vim nano less tmux htop lsof strace cloud-guest-utils btrfs-progs e2fsprogs \
  docker docker-buildx docker-compose
retry pacman -S --noconfirm --needed \
  chromium nss \
  xorg-server-xvfb xorg-xset dbus glib2 at-spi2-core \
  xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-terminal thunar xfce4-settings \
  adwaita-icon-theme ttf-dejavu ttf-liberation noto-fonts-emoji \
  libyuv opus libpulse pulseaudio
systemctl --global disable pulseaudio.service pulseaudio.socket 2>/dev/null || true

mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<JSON
{ "registry-mirrors": ["$MIRROR"], "insecure-registries": ["172.16.0.1:5000"] }
JSON
systemctl enable docker

ca_shim /etc/ca-certificates/trust-source/anchors
# Arch's x264 is a newer soname than voxl links; Ubuntu's sits next to voxl.
install_voxl
environment /usr/bin/chromium
pacman -Scc --noconfirm
finish
