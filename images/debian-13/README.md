# debian-13

Use it with `zode/debian-13`. Debian 13 (trixie), systemd, from Debian's
`genericcloud` image (pin in [line.conf](line.conf)). Any size: the image is
built once at the smallest size and grows (REQ-082).

What it adds to the cloud image ([provision.sh](provision.sh)):

- the Zode guest agent as a systemd unit, hot-plug rules for CPUs and memory,
  root growth when the disk grows
- Docker (Debian's `docker.io`, Buildx, Compose), pulls through the node's mirror
- Git, build tools, CMake, Python 3, Node.js, Go, SQLite, the usual shell tools
- Chromium for `zode browser`, Xfce and voxl for `zode desktop`
- the week's security updates: every build runs `apt-get full-upgrade` and
  boots the upgraded kernel before the snapshot

The software list is the build's `ZODE-MANIFEST` line (`zode-software-report`).
