# arch

Use it with `zode/arch`. Arch Linux (rolling), systemd, btrfs root, from
the official cloud image (pin in [line.conf](line.conf)). Any size (REQ-082).

What it adds ([provision.sh](provision.sh)):

- the Zode guest agent as a systemd unit, hot-plug rules, root growth for
  btrfs (`zode-grow-root.service`)
- `update-ca-certificates` for the agent's CA install (p11-kit anchors)
- Docker (Buildx, Compose), `base-devel`, CMake, Python, Node.js, Go, SQLite
- Chromium for `zode browser`, Xfce and voxl for `zode desktop`; voxl
  carries Ubuntu 24.04's `libx264.so.164` (Arch ships a newer soname)
- every build runs `pacman -Syu` and boots the new kernel, so its modules
  (virtio-mem, overlay for Docker) match the running kernel
