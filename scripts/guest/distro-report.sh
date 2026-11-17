#!/bin/sh
# zode-software-report for the distro lines: the shared report
# (scripts/software-report.sh, installed as
# /usr/local/lib/zode/software-report.sh) plus what the distro's own package
# manager says about the packages that matter in a sandbox. Prints the one
# ZODE-MANIFEST line the control plane stores (docs/official-images.md in
# zode-dev/zoded).
set -u

base=$(bash /usr/local/lib/zode/software-report.sh)
json=${base#ZODE-MANIFEST }

# The packages listed, by their name on each distro. Missing ones are left out.
PKGS="bash ca-certificates chromium coreutils curl docker docker.io moby-engine
docker-cli docker-buildx docker-compose docker-cli-buildx docker-cli-compose
eudev gcc git glibc libc6 musl iproute2 iproute linux-image-cloud-amd64 kernel-core
linux linux-virt nodejs npm openrc openssh openssh-client openssh-clients openssl
python3 python sudo systemd tar xorg-server-xvfb xorg-x11-server-Xvfb xvfb
xfce4-session xfwm4"

rows=$(
  for p in $PKGS; do
    v=""
    n=$p
    if command -v dpkg-query >/dev/null 2>&1; then
      v=$(dpkg-query -W -f='${db:Status-Abbrev}${Version}' "$p" 2>/dev/null | sed -n 's/^ii *//p')
    elif command -v rpm >/dev/null 2>&1; then
      v=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$p" 2>/dev/null | grep -v 'not installed' | head -n1)
    elif command -v pacman >/dev/null 2>&1; then
      # pacman -Q also answers for what a package provides: keep its real name.
      # shellcheck disable=SC2046 # "name version", split on purpose
      set -- $(pacman -Q "$p" 2>/dev/null | head -n1)
      n=${1:-$p}
      v=${2:-}
    elif command -v apk >/dev/null 2>&1; then
      v=$(apk info -e -v "$p" 2>/dev/null | head -n1 | sed "s/^$p-//")
    fi
    [ -n "$v" ] && printf '%s\t%s\n' "$n" "$v"
  done
)
# The agent has no --version: its build is named by the first 12 hex of its sha256.
agent=$(sha256sum /usr/local/bin/zode-agent 2>/dev/null | cut -c1-12)
line=$(cat /etc/zode-line 2>/dev/null)

printf '%s\n' "$rows" | jq -Rnc --argjson m "$json" --arg agent "$agent" --arg line "$line" '
  [inputs | split("\t") | select(length == 2) | {name: .[0], version: .[1]}] | unique_by(.name) as $pkgs
  | $m
  | .groups += [{name: "Installed packages", items: $pkgs}]
  | if $agent != "" then .groups += [{name: "Zode", items: [{name: "zode-agent", version: $agent}]}] else . end
  | if $line != "" then .env = ((.env // {}) + {ZODE_IMAGE_LINE: $line}) else . end' |
  sed 's/^/ZODE-MANIFEST /'
