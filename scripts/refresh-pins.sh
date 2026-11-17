#!/usr/bin/env bash
# Moves each distro line's cloud image pin (images/<line>/line.conf) to the
# newest build its project publishes, with the published checksum, and says
# when a newer release than the line's exists (that is a new line, opened by
# hand: copy the directory, change the pin, drill it).
#
#   scripts/refresh-pins.sh            rewrite the line.conf files in place
#   scripts/refresh-pins.sh --check    print what would change, exit 1 if anything would
#
# Run weekly by .github/workflows/distros.yml. Every build also runs the
# distro's full upgrade, so a week-old pin still ships the week's fixes; the
# pin keeps the first boot (and the kernel the builder starts from) current.
set -euo pipefail
cd "$(dirname "$0")/.."

mode="write"
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

get() { curl -fsSL --retry 4 --retry-all-errors --connect-timeout 20 --max-time 60 "$@"; }
# index URL: the hrefs of a directory listing.
index() { get "$1" | grep -oE 'href="[^"]+"' | sed -E 's/^href="//; s/"$//'; }

changed=0
notes=()

# pin LINE URL SUM: write the pin when it moved.
pin() {
  local conf="images/$1/line.conf" url=$2 sum=$3 old_url old_sum
  if [ -z "$url" ] || [ -z "$sum" ]; then
    echo "$1: could not resolve the newest image" >&2
    return 1
  fi
  old_url=$(sed -n 's/^CLOUD_IMAGE_URL=//p' "$conf")
  old_sum=$(sed -n 's/^CLOUD_IMAGE_SUM=//p' "$conf")
  if [ "$url" = "$old_url" ] && [ "$sum" = "$old_sum" ]; then
    echo "$1: current ($(basename "$url"))"
    return 0
  fi
  echo "$1: $(basename "$old_url") -> $(basename "$url")"
  changed=1
  if [ "$mode" = write ]; then
    sed -i -E "s#^CLOUD_IMAGE_URL=.*#CLOUD_IMAGE_URL=$url#; s#^CLOUD_IMAGE_SUM=.*#CLOUD_IMAGE_SUM=$sum#" "$conf"
  fi
}

# Debian 13: the newest dated build under cloud.debian.org, SHA512SUMS.
debian() {
  local base=https://cloud.debian.org/images/cloud/trixie build file sum
  build=$(index "$base/" | grep -oE '^20[0-9]{6}-[0-9]+' | sort -u | tail -n1)
  file=debian-13-genericcloud-amd64-$build.qcow2
  sum=$(get "$base/$build/SHA512SUMS" | awk -v f="$file" '$2 == f {print $1}')
  pin debian-13 "$base/$build/$file" "sha512:$sum"
}

# Fedora: the line's release, newest Cloud Base Generic compose, CHECKSUM.
fedora() {
  local line rel base file sum newest
  for line in images/fedora-*/; do
    line=$(basename "$line")
    rel=${line#fedora-}
    base=https://dl.fedoraproject.org/pub/fedora/linux/releases/$rel/Cloud/x86_64/images
    file=$(index "$base/" | grep -E '^Fedora-Cloud-Base-Generic-.*\.x86_64\.qcow2$' | sort -V | tail -n1)
    sum=$(get "$base/$(index "$base/" | grep -E 'CHECKSUM$' | sort -V | tail -n1)" |
      sed -nE "s/^SHA256 \($file\) = ([0-9a-f]{64})$/\1/p")
    pin "$line" "$base/$file" "sha256:$sum"
  done
  newest=$(index https://dl.fedoraproject.org/pub/fedora/linux/releases/ | grep -oE '^[0-9]+/$' | tr -d / | sort -n | tail -n1)
  [ -d "images/fedora-$newest" ] || notes+=("Fedora $newest is out: open images/fedora-$newest")
}

# Arch: the newest dated image under images/, its .SHA256.
arch() {
  local base=https://geo.mirror.pkgbuild.com/images build file sum
  build=$(index "$base/" | grep -oE '^v20[0-9]{6}\.[0-9]+/$' | tr -d / | sort -V | tail -n1)
  file=Arch-Linux-x86_64-cloudimg-${build#v}.qcow2
  sum=$(get "$base/$build/$file.SHA256" | awk '{print $1}')
  pin arch "$base/$build/$file" "sha256:$sum"
}

# Alpine: the line's release, newest x86_64 UEFI cloud-init image, .sha512.
alpine() {
  local line rel base file sum newest
  for line in images/alpine-*/; do
    line=$(basename "$line")
    rel=${line#alpine-}
    base=https://dl-cdn.alpinelinux.org/alpine/v$rel/releases/cloud
    file=$(index "$base/" | grep -E "^generic_alpine-$rel\.[0-9]+-x86_64-uefi-cloudinit-r[0-9]+\.qcow2$" | sort -V | tail -n1)
    sum=$(get "$base/$file.sha512" | awk '{print $1}')
    pin "$line" "$base/$file" "sha512:$sum"
  done
  # A release counts once it has a cloud image, not when its repos open.
  for newest in $(index https://dl-cdn.alpinelinux.org/alpine/ | grep -oE '^v3\.[0-9]+/$' | tr -d /v | sort -V | tail -n2); do
    if [ ! -d "images/alpine-$newest" ] && get -o /dev/null "https://dl-cdn.alpinelinux.org/alpine/v$newest/releases/cloud/" 2>/dev/null; then
      notes+=("Alpine $newest has a cloud image: open images/alpine-$newest")
    fi
  done
}

status=0
debian || status=1
fedora || status=1
arch || status=1
alpine || status=1
for n in "${notes[@]}"; do echo "note: $n"; done
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  for n in "${notes[@]}"; do echo "- $n"; done >>"$GITHUB_STEP_SUMMARY"
fi
[ "$status" = 0 ] || exit 1
if [ "$mode" = check ] && [ "$changed" = 1 ]; then exit 1; fi
exit 0
