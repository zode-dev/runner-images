# fedora-45

Use it with `zode/fedora-45`. Fedora 45 Cloud Base, systemd, btrfs root,
SELinux enforcing (pin in [line.conf](line.conf)). Any size (REQ-082).

What it adds ([provision.sh](provision.sh)):

- the Zode guest agent as a systemd unit, hot-plug rules, root growth for
  btrfs (`zode-grow-root.service`)
- `update-ca-certificates`, mirroring `/usr/local/share/ca-certificates`
  into the p11-kit anchors, so the agent's CA install works as on Ubuntu
- Docker (`moby-engine`, Buildx, Compose), Git, GCC, CMake, Python 3,
  Node.js, Go, SQLite
- Chromium for `zode browser`, Xfce and voxl for `zode desktop`. x264 is not
  in Fedora, so voxl carries Ubuntu 24.04's `libx264.so.164` in
  `/usr/local/lib/zode/voxl` (see the NOTICE there)
- every build runs `dnf upgrade` and boots the upgraded kernel
