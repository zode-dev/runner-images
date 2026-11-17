# alpine-3.24

Use it with `zode/alpine-3.24`. Alpine Linux 3.24: musl, OpenRC, ext4,
from the official UEFI cloud-init image (pin in [line.conf](line.conf)).
Any size (REQ-082).

What it adds ([provision.sh](provision.sh)):

- the Zode guest agent as an OpenRC service (supervise-daemon), eudev in
  place of mdev so the CPU and memory hot-plug rules apply
- Docker (Buildx, Compose), `build-base`, CMake, Python 3, Node.js, Go,
  SQLite, bash
- Chromium, for headless use from a shell
- every build runs `apk upgrade --available`

Not on this line: `zode browser` and `zode desktop`. zode-desktop drives
systemd units and voxl is a glibc build; both need work in zode-dev/zoded
before Alpine can switch them on.
