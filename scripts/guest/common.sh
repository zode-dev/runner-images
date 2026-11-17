#!/bin/sh
# Shared steps for the distro lines (images/<line>/provision.sh sources this
# inside the guest on its first boot; scripts/build-base.sh serves it).
#
# POSIX sh on purpose: Alpine has no bash until its provision installs it.
# Everything a Zode sandbox expects from its image, whatever the distro:
#   - zode-agent as a service (systemd, or OpenRC on Alpine), started only
#     on the second boot so a failed provision never makes a golden
#   - hot-added CPUs and memory onlined at once (REQ-082 sizes)
#   - the root file system grows when the disk grows, ext4 or btrfs
#   - update-ca-certificates, which the agent runs for install_ca
#   - voxl (the desktop stream) and the libraries it links, on glibc lines
#   - a plain /etc/resolv.conf (1.1.1.1, 8.8.8.8), as on the Ubuntu base,
#     and systemd-networkd kept off the link the agent manages
#   - on SELinux lines, the bin_t label zode-desktop needs
#   - zode-software-report, printing the ZODE-MANIFEST line
#
# Inputs from scripts/build-base.sh: ZODE_FILES (URL of the served files),
# MIRROR (the node's mirror), ZODE_LINE, ZODE_INIT (systemd|openrc).

log() { printf '%s zode: %s\n' "$(date -u +%H:%M:%S)" "$*"; }
retry() {
  _i=1
  while [ "$_i" -le 5 ]; do
    "$@" && return 0
    log "retry $_i: $*"
    sleep $((_i * 10))
    _i=$((_i + 1))
  done
  return 1
}
fetch() { # URL FILE
  retry curl -fsSL --connect-timeout 20 -o "$2" "$1"
}

# ensure_dns: a resolver while provisioning, when the distro's network
# renderer left /etc/resolv.conf without one (Alpine: cloud-init puts the
# servers in /etc/network/interfaces, which only resolvconf reads).
ensure_dns() {
  grep -q '^nameserver' /etc/resolv.conf 2>/dev/null && return 0
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >/etc/resolv.conf
}

# static_dns: sandboxes resolve through 1.1.1.1 and 8.8.8.8, as the Ubuntu
# base does, from a plain /etc/resolv.conf that nothing rewrites. A restored
# sandbox never re-runs network setup, and systemd-resolved there falls back
# to servers the sandbox network does not answer (seen on Arch: 9.9.9.9).
static_dns() {
  if [ -d /etc/NetworkManager ]; then
    mkdir -p /etc/NetworkManager/conf.d
    printf '[main]\ndns=none\nrc-manager=unmanaged\n' >/etc/NetworkManager/conf.d/90-zode-dns.conf
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable systemd-resolved.service 2>/dev/null || true
  fi
  rm -f /etc/resolv.conf
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >/etc/resolv.conf
}

# quiet_networkd: the agent gives a new sandbox or fork its identity by
# taking eth0 down and up and setting the address and default route itself
# (internal/guestagent/fork.go). systemd-networkd would react to that
# carrier change by reconfiguring the link and deleting the route it did not
# add, leaving the sandbox unreachable for a moment (seen on Arch:
# "network is unreachable" right after create). Keep its hands off.
quiet_networkd() {
  systemctl is-enabled --quiet systemd-networkd.service 2>/dev/null || return 0
  mkdir -p /etc/systemd/networkd.conf.d
  printf '[Network]\nManageForeignRoutes=no\nManageForeignRoutingPolicyRules=no\n' \
    >/etc/systemd/networkd.conf.d/90-zode.conf
  for f in /etc/systemd/network/*.network /run/systemd/network/*.network; do
    [ -e "$f" ] || continue
    d=/etc/systemd/network/$(basename "$f").d
    mkdir -p "$d"
    printf '[Network]\nIgnoreCarrierLoss=yes\nKeepConfiguration=yes\nConfigureWithoutCarrier=yes\n' >"$d/90-zode.conf"
  done
}

# install_files: the agent, zode-desktop and the report scripts.
install_files() {
  mkdir -p /usr/local/lib/zode /var/lib/zode
  fetch "$ZODE_FILES/zode-agent" /usr/local/bin/zode-agent
  chmod 0755 /usr/local/bin/zode-agent
  # zoded also copies zode-desktop in on first use; baking it in saves that.
  fetch "$ZODE_FILES/zode-desktop" /usr/local/lib/zode/zode-desktop
  chmod 0755 /usr/local/lib/zode/zode-desktop
  fetch "$ZODE_FILES/software-report.sh" /usr/local/lib/zode/software-report.sh
  fetch "$ZODE_FILES/distro-report.sh" /usr/local/bin/zode-software-report
  chmod 0755 /usr/local/lib/zode/software-report.sh /usr/local/bin/zode-software-report
  printf '%s\n' "$ZODE_LINE" >/etc/zode-line
}

# hotplug: online hot-added CPUs and memory (zoded grows a restored base to
# the asked size, internal/zoded/sizes.go), and grow the root file system
# when the disk grows. zoded's own grow step runs growpart and resize2fs,
# which covers ext4; on systemd lines a resized disk also starts
# zode-grow-root.service, which covers btrfs (Fedora, Arch). It must not run
# inside the udev event: growpart waits for udev to settle, which waits for
# that same event, and the two deadlock until udev kills the worker.
hotplug() {
  mkdir -p /etc/udev/rules.d /usr/local/lib/zode
  cat >/etc/udev/rules.d/80-zode-hotplug.rules <<'RULES'
SUBSYSTEM=="cpu", ACTION=="add", TEST=="online", ATTR{online}=="0", ATTR{online}="1"
SUBSYSTEM=="memory", ACTION=="add", TEST=="state", ATTR{state}=="offline", ATTR{state}="online_movable"
# The build's cloud-init seed stays attached; keep it off the desktop.
SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="cidata", ENV{UDISKS_IGNORE}="1"
RULES
  if [ "$ZODE_INIT" = systemd ]; then
    cat >>/etc/udev/rules.d/80-zode-hotplug.rules <<'RULES'
SUBSYSTEM=="block", ACTION=="change", KERNEL=="vda", ENV{RESIZE}=="1", RUN+="/usr/bin/systemctl --no-block start zode-grow-root.service"
RULES
    cat >/etc/systemd/system/zode-grow-root.service <<'UNIT'
[Unit]
Description=Zode: grow / to fill its disk
[Service]
Type=oneshot
ExecStart=/usr/local/lib/zode/grow-root
UNIT
  fi
  cat >/usr/local/lib/zode/grow-root <<'GROW'
#!/bin/sh
# Grows the partition holding / and its file system to fill the disk.
# Safe to run at any time; growpart serialises on the disk's lock.
src=$(findmnt -no SOURCE / | sed 's/\[.*//')
fs=$(findmnt -no FSTYPE /)
dev=$(basename "$src")
part=$(cat "/sys/class/block/$dev/partition" 2>/dev/null)
disk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1)
if [ -n "$part" ] && [ -n "$disk" ]; then
  growpart "/dev/$disk" "$part" >/dev/null 2>&1 || true
fi
case "$fs" in
  ext4|ext3|ext2) resize2fs "$src" >/dev/null 2>&1 ;;
  btrfs) btrfs filesystem resize max / >/dev/null 2>&1 ;;
  xfs) xfs_growfs / >/dev/null 2>&1 ;;
esac
exit 0
GROW
  chmod 0755 /usr/local/lib/zode/grow-root
}

# ca_shim: the agent's install_ca writes /usr/local/share/ca-certificates/
# <name>.crt and runs update-ca-certificates (Debian's tool). Fedora and Arch
# use p11-kit anchors instead; this shim keeps the agent's contract there.
ca_shim() { # ANCHOR_DIR
  mkdir -p /usr/local/share/ca-certificates /usr/local/sbin
  cat >/usr/local/sbin/update-ca-certificates <<SHIM
#!/bin/sh
# Zode: the agent's trust-store hook on a p11-kit distro. Mirrors
# /usr/local/share/ca-certificates/*.crt into $1 and rebuilds the bundle.
set -e
anchors=$1
mkdir -p "\$anchors"
rm -f "\$anchors"/zode-local-*.crt
for c in /usr/local/share/ca-certificates/*.crt; do
  [ -e "\$c" ] || continue
  cp "\$c" "\$anchors/zode-local-\$(basename "\$c")"
done
exec update-ca-trust extract
SHIM
  chmod 0755 /usr/local/sbin/update-ca-certificates
}

# voxl: the desktop stream (tembo/voxl, MIT) from the node's pinned inputs.
# It is built on Ubuntu 24.04 and links libx264.so.164, libyuv.so.0,
# libopus.so.0 and libpulse-simple.so.0. The line's provision installs the
# distro's own copies first; any that are still missing come from Ubuntu
# 24.04 (through the node's mirror) into /usr/local/lib/zode/voxl, which only
# voxl sees.
VOXL_VERSION=0.3.5-93ad2d4
install_voxl() {
  dir=/usr/local/lib/zode/voxl
  mkdir -p "$dir"
  fetch "$MIRROR/inputs/voxl/$VOXL_VERSION/voxl" "$dir/voxl.bin"
  fetch "$MIRROR/inputs/voxl/$VOXL_VERSION/voxl.sha256" /tmp/voxl.sha256
  (cd "$dir" && sed "s#voxl\$#voxl.bin#" /tmp/voxl.sha256 | sha256sum -c -)
  chmod 0755 "$dir/voxl.bin"
  missing=$(LD_LIBRARY_PATH=$dir ldd "$dir/voxl.bin" | awk '/not found/ {print $1}')
  for lib in $missing; do
    case "$lib" in
      libx264.so.164) ubuntu_lib universe x264 libx264-164 "$lib" ;;
      libyuv.so.0) ubuntu_lib universe libyuv libyuv0 "$lib" ;;
      libopus.so.0) ubuntu_lib main opus libopus0 "$lib" ;;
      *) log "voxl needs $lib and no line provides it"; return 1 ;;
    esac
  done
  if LD_LIBRARY_PATH=$dir ldd "$dir/voxl.bin" | grep 'not found' >/dev/null; then
    log "voxl still misses a library"
    LD_LIBRARY_PATH=$dir ldd "$dir/voxl.bin"
    return 1
  fi
  cat >/usr/local/bin/voxl <<WRAP
#!/bin/sh
# voxl with the libraries it was built against (see $dir/NOTICE).
LD_LIBRARY_PATH=$dir\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH} exec $dir/voxl.bin "\$@"
WRAP
  chmod 0755 /usr/local/bin/voxl
  voxl --version
  cat >"$dir/NOTICE" <<NOTICE
voxl $VOXL_VERSION, the desktop streamer in this image.

voxl is MIT licensed: https://github.com/tembo/voxl (commit ${VOXL_VERSION#*-}).
It links libx264 (GPL-2.0-or-later), libyuv (BSD-3-Clause), Opus
(BSD-3-Clause) and libpulse (LGPL-2.1-or-later), so voxl as a whole is
distributed under GPL-2.0-or-later. Libraries in this directory come from
Ubuntu 24.04 (${missing:-none needed}); their sources: apt-get source x264
libyuv opus on Ubuntu 24.04. voxl is built by deploy/node/voxl-input.sh in
https://github.com/zode-dev/zoded (or ask support@zode.dev for a copy).
NOTICE
}

# ubuntu_lib COMPONENT SOURCE PACKAGE SONAME: one shared library out of an
# Ubuntu 24.04 package, through the node's apt mirror.
ubuntu_lib() {
  t=$(mktemp -d)
  for suite in noble-updates noble-security noble; do
    if fetch "$MIRROR/apt/$suite/dists/$suite/$1/binary-amd64/Packages.gz" "$t/Packages.gz"; then
      f=$(gzip -dc "$t/Packages.gz" | awk -v p="$3" '$1 == "Package:" {pk = $2} $1 == "Filename:" && pk == p {print $2; exit}')
      [ -n "$f" ] && break
    fi
  done
  [ -n "$f" ] || { log "no $3 in the Ubuntu mirror"; return 1; }
  fetch "$MIRROR/apt/$suite/$f" "$t/p.deb"
  # Ubuntu 24.04 packages carry data.tar.zst: needs ar (binutils) and zstd.
  (cd "$t" && ar x p.deb && mkdir root && tar -C root -xf data.tar.*)
  so=$(find "$t/root" -name "$4*" -type f | head -n1)
  [ -n "$so" ] || { log "no $4 in $3"; return 1; }
  cp "$so" "/usr/local/lib/zode/voxl/$4"
  log "voxl: $4 from Ubuntu $3 ($(basename "$f"))"
  rm -rf "$t"
}

# selinux_bin: on SELinux lines (Fedora) the Zode helpers in
# /usr/local/lib/zode must be bin_t. Otherwise zode-desktop runs as init_t
# and may not connect to the Xvfb it starts (unconfined_service_t): the
# desktop never comes up. New files there (zoded copies a newer
# zode-desktop in) take the directory's label.
selinux_bin() {
  mkdir -p /usr/local/lib/zode
  semanage fcontext -a -t bin_t '/usr/local/lib/zode(/.*)?' 2>/dev/null ||
    semanage fcontext -m -t bin_t '/usr/local/lib/zode(/.*)?'
  restorecon -R /usr/local/lib/zode
}

# quiet_desktop: a sandbox desktop has no polkit session, so Xfce's polkit
# agent only opens an error dialog at login (seen on Fedora). The Ubuntu
# base does not start one either.
quiet_desktop() {
  rm -f /etc/xdg/autostart/xfce-polkit.desktop /etc/xdg/autostart/polkit-gnome-authentication-agent-1.desktop
}

# environment: the same variables the Ubuntu base sets, where they apply.
environment() { # CHROME_BIN
  cat >/etc/profile.d/zode.sh <<EOF
export CHROME_PATH=$1
export PUPPETEER_EXECUTABLE_PATH=$1
# With the browser switched on (zode browser <sb> --on), drive that Chrome:
#   npx @playwright/mcp --cdp-endpoint \$ZODE_CDP_URL
export ZODE_CDP_URL=http://127.0.0.1:9222
export AGENT_BROWSER_AUTO_CONNECT=1
EOF
  mkdir -p /workspace
}

# agent_service: zode-agent under the line's init, enabled for the next boot
# only, plus a one-shot that writes the software manifest on that boot.
agent_service() {
  mkdir -p /etc/zode-agent
  if [ "$ZODE_INIT" = openrc ]; then
    cat >/etc/init.d/zode-agent <<'RC'
#!/sbin/openrc-run
description="Zode guest agent"
command=/usr/local/bin/zode-agent
command_args="-token-file /etc/zode-agent/token"
supervisor=supervise-daemon
respawn_delay=1
respawn_max=0
output_log=/var/log/zode-agent.log
error_log=/var/log/zode-agent.log
depend() {
  need net
  after zode-manifest
}
RC
    cat >/etc/init.d/zode-manifest <<'RC'
#!/sbin/openrc-run
description="Zode: write the software manifest once"
depend() { after docker; }
start() {
  [ -e /var/lib/zode/manifest.json ] && return 0
  ebegin "Writing the Zode software manifest"
  /usr/local/bin/zode-software-report >/var/lib/zode/manifest.txt 2>/var/lib/zode/manifest.err
  sed -n 's/^ZODE-MANIFEST //p' /var/lib/zode/manifest.txt >/var/lib/zode/manifest.json
  cat /var/lib/zode/manifest.txt >/dev/ttyS0 2>/dev/null
  eend 0
}
RC
    chmod 0755 /etc/init.d/zode-agent /etc/init.d/zode-manifest
    rc-update add zode-manifest default
    rc-update add zode-agent default
  else
    cat >/etc/systemd/system/zode-agent.service <<'UNIT'
[Unit]
Description=Zode guest agent
After=network.target zode-manifest.service
[Service]
ExecStart=/usr/local/bin/zode-agent -token-file /etc/zode-agent/token
Restart=always
RestartSec=1
# Commands run by the agent live in its cgroup; one OOM kill must not stop
# the unit (same as the Ubuntu base).
OOMPolicy=continue
[Install]
WantedBy=multi-user.target
UNIT
    cat >/etc/systemd/system/zode-manifest.service <<'UNIT'
[Unit]
Description=Zode: write the software manifest once
After=docker.service network-online.target
ConditionPathExists=!/var/lib/zode/manifest.json
[Service]
Type=oneshot
ExecStart=/bin/sh -c '/usr/local/bin/zode-software-report >/var/lib/zode/manifest.txt 2>/var/lib/zode/manifest.err; sed -n "s/^ZODE-MANIFEST //p" /var/lib/zode/manifest.txt >/var/lib/zode/manifest.json; cat /var/lib/zode/manifest.txt >/dev/ttyS0'
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable zode-manifest.service zode-agent.service
  fi
}

# finish: the last provision step. The golden is the second boot: the
# upgraded kernel runs, the agent starts, scripts/build-base.sh snapshots it.
finish() {
  install_files
  hotplug
  agent_service
  static_dns
  quiet_networkd
  quiet_desktop
  if command -v restorecon >/dev/null 2>&1 && [ -d /sys/fs/selinux ]; then
    restorecon -R /usr/local/lib/zode /usr/local/bin /usr/local/sbin /etc/systemd/system /etc/resolv.conf
  fi
  # cloud-init ran once; keep it from touching a restored sandbox again.
  touch /etc/cloud/cloud-init.disabled 2>/dev/null || true
  rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
  sync
  touch /var/lib/zode/provisioned
  log "provisioned $ZODE_LINE; rebooting into the golden"
  echo ZODE_PROVISION_DONE >/dev/ttyS0 2>/dev/null || true
}
