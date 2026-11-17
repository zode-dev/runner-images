#!/usr/bin/env bash
# Builds a distro line (images/<line>/line.conf + provision.sh) into a
# growable golden on a Zode node: the distro's cloud image, the zode agent,
# the line's packages, booted twice (the second boot runs the upgraded
# kernel) and snapshotted with disk and RAM. zoded serves every size from it
# (zoded serve --base <name>, internal/zoded/sizes.go, REQ-082).
#
#   scripts/build-base.sh LINE [NAME]     as root on a node, from a checkout
#
# NAME defaults to <line>-<UTC date>, dots made hyphens (alpine-3-24-20261117). Needs on the node: zoded (agent-ping),
# /usr/local/bin/zode-agent, /usr/local/lib/zode/zode-desktop, cloud-localds
# (cloud-image-utils), qemu-img, the mirror on :5000 and outbound internet
# (the distro's own package mirrors). Same build network as zoded's
# deploy/node/make-base.sh; that script builds the Ubuntu base itself.
#
# Environment: POOL (zode), CPUS (2), RAM (4G), MAX_CPUS (16), MAX_RAM (32G),
# DISK_GB (50), TIMEOUT_MIN (60), SLOT (0..63: the build link 10.199.SLOT.0/30,
# so several lines can build on one node at once).
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 LINE [NAME]" >&2; exit 2; }
LINE=$1
REPO=$(cd "$(dirname "$0")/.." && pwd)
CONF=$REPO/images/$LINE/line.conf
PROV=$REPO/images/$LINE/provision.sh
if [ ! -f "$CONF" ] || [ ! -f "$PROV" ]; then echo "images/$LINE is not a distro line (line.conf + provision.sh)" >&2; exit 1; fi
# shellcheck source=/dev/null
. "$CONF"
: "${CLOUD_IMAGE_URL:?line.conf needs CLOUD_IMAGE_URL}" "${CLOUD_IMAGE_SUM:?line.conf needs CLOUD_IMAGE_SUM}" "${INIT:?line.conf needs INIT}"

# A golden name is zoded's sandbox id shape (no dots), short enough that
# the derived <name>-xlarge still fits.
NAME=${2:-${LINE//./-}-$(date -u +%Y%m%d)}
[[ $NAME =~ ^[a-z0-9][a-z0-9-]{0,33}$ ]] || { echo "golden name $NAME: want ^[a-z0-9][a-z0-9-]{0,33}$" >&2; exit 2; }
POOL=${POOL:-zode}
CPUS=${CPUS:-2}
RAM=${RAM:-4G}
MAX_CPUS=${MAX_CPUS:-16}
MAX_RAM=${MAX_RAM:-32G}
DISK_GB=${DISK_GB:-50}
TIMEOUT_MIN=${TIMEOUT_MIN:-60}
SLOT=${SLOT:-0}
case "$SLOT" in [0-9]|[1-5][0-9]|6[0-3]) ;; *) echo "SLOT must be 0 to 63" >&2; exit 2 ;; esac
HOST_IP=10.199.$SLOT.1
NS_IP=10.199.$SLOT.2
ram_g=${RAM%G}
max_g=${MAX_RAM%G}
[ "$max_g" -gt "$ram_g" ] || { echo "MAX_RAM must be above RAM (in G)" >&2; exit 1; }

W=/var/lib/zode/golden/$NAME
SRC=/var/lib/zode/golden-src
TOKEN_FILE=/etc/zode/agent.token
AGENT=/usr/local/bin/zode-agent
DESKTOP=/usr/local/lib/zode/zode-desktop
NS="g-$NAME"
VG="vg-${NAME:0:12}"
VN="vn-${NAME:0:12}"
for need in "$AGENT" "$DESKTOP"; do [ -x "$need" ] || { echo "missing $need" >&2; exit 1; }; done
for need in zoded cloud-hypervisor ch-remote cloud-localds qemu-img zfs nft; do
  command -v "$need" >/dev/null || { echo "missing $need on PATH" >&2; exit 1; }
done
[ -s "$TOKEN_FILE" ] || { echo "missing $TOKEN_FILE (comes with the node's goldens)" >&2; exit 1; }
curl -fsS -o /dev/null http://127.0.0.1:5000/healthz || { echo "the mirror (zoded) is not answering on :5000" >&2; exit 1; }

if zfs list "$POOL/golden/$NAME" >/dev/null 2>&1; then
  if zfs get -H -o value clones "$POOL/golden/$NAME@ram" 2>/dev/null | grep -v '^-$' | grep . >/dev/null; then
    echo "$POOL/golden/$NAME@ram has live clones; build under another NAME" >&2; exit 1
  fi
fi

cleanup_net() {
  ip link del "$VG" 2>/dev/null || true
  ip netns del "$NS" 2>/dev/null || true
  nft delete table ip "zg_$LINE" 2>/dev/null || true
}
zfs destroy -r "$POOL/snap/$NAME" 2>/dev/null || true
zfs destroy -r "$POOL/golden/$NAME" 2>/dev/null || true
cleanup_net
mkdir -p "$W" "$SRC"
cd "$W"
rm -f api.sock vsock.sock serial.log manifest.json

# 1. The distro's cloud image, checked against the pinned sum.
img=$SRC/$(basename "$CLOUD_IMAGE_URL")
algo=${CLOUD_IMAGE_SUM%%:*}
want=${CLOUD_IMAGE_SUM#*:}
case "$algo" in sha256|sha512) ;; *) echo "CLOUD_IMAGE_SUM must be sha256:... or sha512:..." >&2; exit 1 ;; esac
if [ ! -f "$img" ] || [ "$("${algo}sum" "$img" | cut -d' ' -f1)" != "$want" ]; then
  curl -fsSL --retry 6 --retry-all-errors --connect-timeout 20 -o "$img.part" "$CLOUD_IMAGE_URL"
  got=$("${algo}sum" "$img.part" | cut -d' ' -f1)
  [ "$got" = "$want" ] || { echo "$CLOUD_IMAGE_URL: $algo $got, want $want" >&2; rm -f "$img.part"; exit 1; }
  mv "$img.part" "$img"
fi
qemu-img convert -O raw "$img" disk.raw
zfs create -s -V "${DISK_GB}G" -o volblocksize=16k "$POOL/golden/$NAME"
udevadm settle
dd if=disk.raw of="/dev/zvol/$POOL/golden/$NAME" bs=4M conv=sparse status=none
rm -f disk.raw

# 2. cloud-init: the agent token, the build network, and one command that
# fetches the line's provision and runs it. Success reboots into the golden
# (the agent starts on that boot only); failure prints a marker.
TOKEN=$(cat "$TOKEN_FILE")
cat >user-data <<EOF
#cloud-config
hostname: zode
ssh_pwauth: false
write_files:
  - path: /etc/zode-agent/token
    permissions: '0400'
    content: $TOKEN
runcmd:
  - [sh, -c, "mkdir -p /root/zode && cd /root/zode && for f in common.sh provision.sh; do curl -fsS --retry 5 -o \$f http://$HOST_IP:8099/\$f || wget -q -O \$f http://$HOST_IP:8099/\$f; done; if ZODE_FILES=http://$HOST_IP:8099 MIRROR=http://172.16.0.1:5000 ZODE_LINE=$LINE ZODE_INIT=$INIT sh /root/zode/provision.sh >/var/log/zode-provision.log 2>&1; then reboot; else tail -n 60 /var/log/zode-provision.log >/dev/ttyS0; echo ZODE_PROVISION_FAILED >/dev/ttyS0; fi"]
EOF
cat >network-config <<'EOF'
version: 2
ethernets:
  eth0:
    match: { macaddress: "12:34:56:78:90:01" }
    set-name: eth0
    addresses: [172.16.0.2/24]
    routes: [{ to: default, via: 172.16.0.1 }]
    nameservers: { addresses: [1.1.1.1, 8.8.8.8] }
EOF
echo "instance-id: $NAME-$(date +%s)" >meta-data
cloud-localds --network-config=network-config seed.img user-data meta-data

# 3. The build namespace: guest -> tap0 -> ns -> veth -> host, internet by
# NAT and the node's mirror at 172.16.0.1:5000 (as in make-base.sh).
ip netns add "$NS"
ip netns exec "$NS" ip link set lo up
ip link add "$VG" type veth peer name "$VN"
ip link set "$VN" netns "$NS"
ip addr add "$HOST_IP/30" dev "$VG" && ip link set "$VG" up
ip netns exec "$NS" ip addr add "$NS_IP/30" dev "$VN"
ip netns exec "$NS" ip link set "$VN" up
ip netns exec "$NS" ip route add default via "$HOST_IP"
sysctl -qw net.ipv4.ip_forward=1
ip netns exec "$NS" sysctl -qw net.ipv4.ip_forward=1
UPLINK=$(ip route show default | awk '{print $5; exit}')
nft -f - <<NFT
table ip zg_$LINE {
  chain post { type nat hook postrouting priority 100; ip saddr 10.199.$SLOT.0/30 oifname "$UPLINK" masquerade; }
}
NFT
ip netns exec "$NS" nft -f - <<NFT
table ip zg_$LINE {
  chain pre { type nat hook prerouting priority -100; ip daddr 172.16.0.1 tcp dport 5000 dnat to $HOST_IP:5000; }
  chain post { type nat hook postrouting priority 100; oifname "$VN" masquerade; }
}
NFT

mkdir -p www
cp "$AGENT" www/zode-agent
cp "$DESKTOP" www/zode-desktop
cp "$REPO/scripts/guest/common.sh" "$REPO/scripts/guest/distro-report.sh" "$REPO/scripts/software-report.sh" www/
cp "$PROV" www/provision.sh
python3 -m http.server 8099 --bind "$HOST_IP" --directory "$W/www" >/dev/null 2>&1 &
HTTP_PID=$!
CH_PID=""
trap 'kill $HTTP_PID 2>/dev/null || true; [ -n "$CH_PID" ] && kill "$CH_PID" 2>/dev/null; cleanup_net' EXIT

ip netns exec "$NS" cloud-hypervisor \
  --api-socket "path=$W/api.sock" \
  --firmware /var/lib/zode/CLOUDHV.fd \
  --cpus "boot=$CPUS,max=$MAX_CPUS" \
  --memory "size=$RAM,shared=on,hotplug_method=virtio-mem,hotplug_size=$((max_g - ram_g))G" \
  --disk "path=/dev/zvol/$POOL/golden/$NAME,image_type=raw" "path=$W/seed.img,readonly=on,image_type=raw" \
  --net "tap=tap0,mac=12:34:56:78:90:01,ip=172.16.0.1,mask=255.255.255.0" \
  --vsock "cid=3,socket=$W/vsock.sock" \
  --serial "file=$W/serial.log" --console off &
CH_PID=$!

# 4. Wait for the agent: it is enabled by the provision and first starts
# on the second boot, after the manifest one-shot.
echo "building $LINE as $NAME; first boot provisions (see serial.log), the second runs the agent"
deadline=$(($(date +%s) + TIMEOUT_MIN * 60))
until zoded agent-ping "$W/vsock.sock" "$TOKEN_FILE" >/dev/null 2>&1; do
  kill -0 "$CH_PID" 2>/dev/null || { echo "VMM exited; see $W/serial.log" >&2; exit 1; }
  if grep -aq ZODE_PROVISION_FAILED "$W/serial.log" 2>/dev/null; then
    echo "provision failed; the last lines:" >&2
    grep -av '^\s*$' "$W/serial.log" | tail -n 70 >&2
    exit 1
  fi
  [ "$(date +%s)" -lt "$deadline" ] || { echo "no agent after $TIMEOUT_MIN minutes" >&2; tail -n 40 "$W/serial.log" >&2; exit 1; }
  sleep 5
done
zoded agent-ping "$W/vsock.sock" "$TOKEN_FILE"
grep -ao 'ZODE-MANIFEST {.*}' "$W/serial.log" | tail -n1 | sed 's/^ZODE-MANIFEST //' >manifest.json
if ! jq -e '.os and (.groups | length > 0)' manifest.json >/dev/null 2>&1; then
  echo "no ZODE-MANIFEST line on the serial console" >&2; exit 1
fi
echo "manifest: $(jq -r .os manifest.json), $(jq '[.groups[].items[]] | length' manifest.json) entries"
# Let services settle (Docker, udev) before the freeze.
sleep 15

# 5. Snapshot disk and RAM at the same instant.
zfs create "$POOL/snap/$NAME"
ch-remote --api-socket "$W/api.sock" pause
t0=$(date +%s%N)
ch-remote --api-socket "$W/api.sock" snapshot "file:///$POOL/snap/$NAME"
t1=$(date +%s%N)
zfs snapshot "$POOL/golden/$NAME@ram"
zfs snapshot "$POOL/snap/$NAME@ram"
echo "ram_save_ms=$(((t1 - t0) / 1000000)) size=$(du -sh "/$POOL/snap/$NAME" | cut -f1)" | tee save.txt
ch-remote --api-socket "$W/api.sock" shutdown-vmm || kill "$CH_PID"
wait "$CH_PID" 2>/dev/null || true
CH_PID=""
echo "golden $NAME ready ($LINE): $POOL/golden/$NAME@ram + $POOL/snap/$NAME@ram; serve it with zoded serve --base $NAME"
