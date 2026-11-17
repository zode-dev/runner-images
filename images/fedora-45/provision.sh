#!/bin/sh
# fedora-45: runs as root inside the guest on its first boot
# (scripts/build-base.sh). Packages from Fedora's mirrors with updates, so
# every rebuild carries the week's security updates. Root is btrfs: the
# grow hook in common.sh resizes it.
set -eux
# shellcheck source=scripts/guest/common.sh
. /root/zode/common.sh

retry dnf -y upgrade --refresh
retry dnf -y install --setopt=install_weak_deps=False \
  ca-certificates curl wget2-wget gnupg2 git jq unzip zip xz zstd ripgrep fd-find tree \
  gcc gcc-c++ make pkgconf-pkg-config openssl-devel cmake binutils \
  python3 python3-pip python3-devel pipx nodejs npm golang \
  sqlite iproute iputils bind-utils nmap-ncat openssh-clients sudo \
  vim-enhanced nano less tmux htop lsof strace cloud-utils-growpart btrfs-progs e2fsprogs \
  moby-engine docker-buildx docker-compose policycoreutils-python-utils grubby
retry dnf -y install --setopt=install_weak_deps=False \
  chromium nss-tools \
  xorg-x11-server-Xvfb xset dbus-x11 dbus-daemon glib2 at-spi2-core \
  xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-terminal Thunar xfce4-settings \
  adwaita-icon-theme dejavu-sans-fonts liberation-fonts google-noto-color-emoji-fonts \
  libyuv opus pulseaudio-libs pulseaudio
systemctl --global disable pulseaudio.service pulseaudio.socket 2>/dev/null || true

mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<JSON
{ "registry-mirrors": ["$MIRROR"], "insecure-registries": ["172.16.0.1:5000"] }
JSON
systemctl enable docker

# The NIC is eth0 on every line (the agent's fork step and the build's
# network config name it); Fedora keeps predictable names without this.
grubby --update-kernel=ALL --args=net.ifnames=0
# SELinux stays enforcing; the Zode helpers get the label they need.
selinux_bin

# The agent's install_ca calls update-ca-certificates; Fedora has p11-kit.
ca_shim /etc/pki/ca-trust/source/anchors
# x264 is not in Fedora; voxl gets Ubuntu's libx264.so.164 next to it.
install_voxl
environment /usr/bin/chromium-browser
dnf clean all
finish
