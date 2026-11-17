#!/usr/bin/env bash
# Checks the distro lines (images/<line>/line.conf + provision.sh): the
# pin is an https URL with a sha256 or sha512 checksum, the init is one the
# agent service knows, the provision sources common.sh and ends with
# finish, and no directory is both a Dockerfile line and a distro line.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
fail() { echo "$1: $2" >&2; status=1; }
found=0
for conf in images/*/line.conf; do
  [ -e "$conf" ] || continue
  found=1
  dir=$(dirname "$conf")
  line=$(basename "$dir")
  [[ $line =~ ^[a-z0-9][a-z0-9.-]{0,40}$ ]] || fail "$line" "line name must match ^[a-z0-9][a-z0-9.-]{0,40}$"
  url=$(sed -n 's/^CLOUD_IMAGE_URL=//p' "$conf")
  sum=$(sed -n 's/^CLOUD_IMAGE_SUM=//p' "$conf")
  init=$(sed -n 's/^INIT=//p' "$conf")
  name=$(sed -n 's/^DISTRO_NAME=//p' "$conf")
  [[ $url =~ ^https://[^[:space:]]+\.(qcow2|img|raw)$ ]] || fail "$line" "CLOUD_IMAGE_URL must be an https URL of a qcow2/img/raw image"
  [[ $sum =~ ^sha256:[0-9a-f]{64}$ || $sum =~ ^sha512:[0-9a-f]{128}$ ]] || fail "$line" "CLOUD_IMAGE_SUM must be sha256:<64 hex> or sha512:<128 hex>"
  [[ $init == systemd || $init == openrc ]] || fail "$line" "INIT must be systemd or openrc"
  [ -n "$name" ] || fail "$line" "DISTRO_NAME is empty"
  prov=$dir/provision.sh
  if [ ! -f "$prov" ]; then
    fail "$line" "no provision.sh"
    continue
  fi
  grep -qx '\. /root/zode/common.sh' "$prov" || fail "$line" "provision.sh must source /root/zode/common.sh"
  [ "$(grep -v '^[[:space:]]*$' "$prov" | tail -n1)" = finish ] || fail "$line" "provision.sh must end with finish"
  [ ! -e "$dir/Dockerfile.in" ] || fail "$line" "a line is a Dockerfile line or a distro line, not both"
done
[ "$found" = 1 ] || fail images "no distro lines"
exit "$status"
