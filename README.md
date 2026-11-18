# Zode runner images

The source of Zode's official images: the images every Zode sandbox and
every GitHub Actions job on Zode can boot. It plays the part
[actions/runner-images](https://github.com/actions/runner-images) plays for
GitHub-hosted runners.

Each line is one Dockerfile under `images/`. Zode builds it on every node
and in every size, and publishes all of them at once.

## Lines

| Line | Used by | What it adds to the Zode base image |
| --- | --- | --- |
| [`ci-ubuntu-24.04`](images/ci-ubuntu-24.04) | every CI job (`runs-on: zode-*`) | what GitHub's `ubuntu-24.04` carries that common actions and workflows use: the hosted tool cache (Node.js 22 and 24, Python 3.11 to 3.15, Go 1.24 to 1.26, Temurin 8 to 25), the Android SDK at GitHub's path (`ANDROID_HOME`, cmdline-tools, platforms 34 to 37.2, build-tools 34 to 37, NDK 27/29/30, CMake, platform-tools), Maven, Gradle, PowerShell, Azure, Google Cloud and AWS CLIs, Kubernetes tools, Firefox and the browser drivers, rustup, a `runner` user with passwordless sudo, Zode's `zode-ci` test wrapper, GitHub's apt package list and kernel settings; PostgreSQL, MySQL and Redis installed but stopped. What still differs is in [PARITY.md](images/ci-ubuntu-24.04/PARITY.md) |
| [`base`](images/base) | sandboxes that ask for `zode/base` | zstd, Git LFS, yq; PostgreSQL and Redis keep running |
| [`ubuntu-24.04`](images/ubuntu-24.04) | `zode/ubuntu-24.04`, and old size names | nothing but the security updates since the base was built |
| [`android`](images/android) | sandboxes that ask for `zode/android` (held, not released yet) | Android (AOSP x86_64/x86 in a container, redroid), adb and scrcpy; its screen is the sandbox desktop. Temurin 21 and the Android SDK (platforms and build-tools 35/36) to build an app and install it on the phone in one sandbox. No Google Play, no ARM translation |

The Linux distro lines (REQ-084) are built from each distro's own cloud
image, not from the Zode base, so they are a different kind of line (see
[Distro lines](#distro-lines)):

| Line | Init | Browser and desktop | Built from |
| --- | --- | --- | --- |
| [`debian-13`](images/debian-13) | systemd | yes | Debian 13 `genericcloud` |
| [`fedora-45`](images/fedora-45) | systemd | yes | Fedora 45 Cloud Base Generic |
| [`arch`](images/arch) | systemd | yes | Arch Linux cloud image |
| [`alpine-3.24`](images/alpine-3.24) | OpenRC | no (shell, Docker, headless Chromium) | Alpine 3.24 UEFI cloud-init |

The Zode base image itself is Ubuntu 24.04 with Docker (Buildx, Compose),
Node.js, pnpm, Yarn, Bun, Python, Go, Rust, the GitHub CLI, Chrome,
Playwright, PostgreSQL, Redis and the coding agents.

## Use them

CI jobs get `ci-ubuntu-24.04` with nothing to change:

```yaml
jobs:
  test:
    runs-on: zode-4x8
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v6
        with:
          node-version: 24 # found in the tool cache, no download
```

A sandbox asks for a line by name and keeps its own size:

```sh
zode new --image zode/base
```

In the API: `"image": "zode/<line>"` on `POST /v1/sandboxes`.

## Software

The lists below come from each image's own report
(`zode-software-report`, the last build step). The publish workflow writes
them after every release.

<!-- software:start -->
| Line | Use it with | Version | Published | Software |
| --- | --- | --- | --- | --- |
| `android` | `zode/android` | 20261118.29 | 2026-11-18 | [images/android](images/android/README.md) |
| `arch` | `zode/arch` | 20261118.31 | 2026-11-18 | [images/arch](images/arch/README.md) |
| `base` | `zode/base` | 20261112.4 | 2026-11-12 | [images/base](images/base/README.md) |
| `ci-ubuntu-24.04` | `zode/ci-ubuntu-24.04` | 20261117.25 | 2026-11-17 | [images/ci-ubuntu-24.04](images/ci-ubuntu-24.04/README.md) |
| `debian-13` | `zode/debian-13` | 20261118.28 | 2026-11-18 | [images/debian-13](images/debian-13/README.md) |
| `fedora-45` | `zode/fedora-45` | 20261118.30 | 2026-11-18 | [images/fedora-45](images/fedora-45/README.md) |
| `ubuntu-24.04` | `zode/ubuntu-24.04` | 20261118.33 | 2026-11-18 | [images/ubuntu-24.04](images/ubuntu-24.04/README.md) |
<!-- software:end -->

## Parity with GitHub's image

`ci-ubuntu-24.04` aims to run workflows written for GitHub's `ubuntu-24.04`
with only `runs-on` changed. `scripts/parity.sh` compares the line's software
report with the one GitHub attaches to every
[actions/runner-images](https://github.com/actions/runner-images/releases)
release (`internal.ubuntu24.json`). The publish workflow writes the result
to [images/ci-ubuntu-24.04/PARITY.md](images/ci-ubuntu-24.04/PARITY.md) and
into the GitHub release of every image version. Why something is left out
is kept in `images/ci-ubuntu-24.04/parity.tsv`.

```sh
scripts/parity.sh ci-ubuntu-24.04            # published image vs GitHub's latest
scripts/parity.sh --manifest m.json ci-ubuntu-24.04   # a local software report
```

## zode-ci in the image

`ci-ubuntu-24.04` has an install hook for `zode-ci`, the test wrapper from
zode-dev/zoded (`cmd/zode-ci`). It is off while `ARG ZODE_CI_URL` is empty.
To ship a release, set `ZODE_CI_URL` to
`https://api.zode.dev/dl/zode-ci-linux-amd64` and `ZODE_CI_SHA256` to its line
in `https://api.zode.dev/dl/SHA256SUMS` in `Dockerfile.in`, render and merge:
the step installs it at `/usr/local/bin/zode-ci` and runs
`zode-ci --version`. Until then the runner start script fetches it from
`/dl` for every job.

## How a release works

1. A push to `main` that changes `images/<line>/Dockerfile` (or a distro
   line's `line.conf` or `provision.sh`) starts the
   [publish workflow](.github/workflows/publish.yml) for that line. A change
   to `scripts/software-report.sh` releases every line, one to
   `scripts/guest/` every distro line. A maintainer can also run it by hand
   for one line or all of them.
2. The workflow sends the Dockerfile to `POST /v1/official/releases`,
   signed with its GitHub OIDC token. Only this repository's `main` branch
   is accepted. The version is `YYYYMMDD.<run number>`.
3. Zode builds the image once per node and per size, one official build per
   node at a time so customer sandboxes keep their room.
4. When every build is ready, the release is published everywhere at once.
   New sandboxes and CI jobs use it from then on. The previous release is
   retired and its images are deleted after 24 hours; sandboxes already
   running from it keep running.
5. If any build fails, the release fails, the other builds are cancelled and
   the published release stays as it was. The workflow prints each failed
   build's log.
6. The workflow then writes `images/<line>/README.md` and the table above
   from the public catalogue (`GET https://api.zode.dev/v1/official-images`),
   `images/<line>/PARITY.md` for a line with a `parity.tsv`, and a GitHub
   release `<line>/<version>` carrying the difference list.

## How a Dockerfile is read

Lines build `FROM zode`, so each step runs in a Zode VM, not in a container:

- every `RUN` runs with `bash -lc` as root;
- `ENV` is kept for every login shell (`/etc/profile.d`) and in
  `/etc/environment`; `ARG` is for the build only;
- `COPY` and `ADD` are refused, so files are written inline with a heredoc;
- a Dockerfile is at most 64 KB and 200 instructions, a step at most 16 KB,
  and a build at most 60 minutes.

## Contributing

- Edit `images/<line>/Dockerfile.in`, never the `Dockerfile` next to it.
  Run `scripts/render.sh` and commit both. The render copies
  `scripts/software-report.sh` into every Dockerfile, because the image cannot
  copy it in.
- Pin every version in an `ARG` at the top of the file, with its sha256
  when the project publishes one.
- Keep the last step `RUN /usr/local/bin/zode-software-report`. It prints
  the one `ZODE-MANIFEST {...}` line Zode stores with the release.
- Pull requests run [check](.github/workflows/check.yml): shellcheck,
  the render check, hadolint, actionlint and a smoke test of the report.
- Keep the images lean. Large toolchains (.NET, Haskell, Swift)
  belong in a workspace's own custom image, not here. The Android SDK is the
  exception (owner, 17 Nov 2026): `ci-ubuntu-24.04` carries GitHub's layout
  (12 GB) and `android` the pieces for `./gradlew assembleDebug`.

To add a line, create `images/<name>/Dockerfile.in`, render it, and merge.
The name must match `^[a-z0-9][a-z0-9.-]{0,40}$`.

## Distro lines

A distro line is `images/<line>/line.conf` (the cloud image URL and its
checksum, the init system) and `images/<line>/provision.sh` (what the line
installs), with the shared guest steps in `scripts/guest/common.sh`: the
zode agent under systemd or OpenRC, CPU and memory hot-plug rules, root
growth for ext4 and btrfs, `update-ca-certificates` where the distro uses
p11-kit, voxl for the desktop with the libraries it links, a static
resolver, and `zode-software-report` with the distro's package list.

On a node, as root:

```sh
scripts/build-base.sh debian-13              # golden debian-13-<date>, growable
zoded serve ... --base debian-13-<date>      # every size from that one build
scripts/matrix.sh debian-13                  # boot, exec, Docker, fork, desktop at every size
```

`build-base.sh` boots the cloud image at the smallest size with room to
grow (16 vCPUs, virtio-mem up to 32 GB), runs the provision on the first
boot (including the distro's full upgrade), reboots into the upgraded
kernel, waits for the agent and snapshots disk and RAM, like
`deploy/node/make-base.sh` in zode-dev/zoded does for the Ubuntu base. The
`ZODE-MANIFEST` line is written on the second boot and kept next to the
golden as `manifest.json`. `SLOT=<n>` builds several lines on one node at
once.

The publish workflow releases a distro line as a recipe: `scripts/release.sh`
sends `POST /v1/official/releases` with `recipe` (the cloud image pin and
init from `line.conf`, `provision.sh` and the shared guest scripts) instead
of a `dockerfile`. Every node on a growable base with the `recipe_images`
feature builds it the way `build-base.sh` does (zoded
`internal/zoded/recipe.go`), once, at the smallest size, and serves it at
every size; nodes still on per-size goldens skip it. `build-base.sh` stays
for drills and for building a line by hand on one node.

Every Monday the [distros workflow](.github/workflows/distros.yml) moves
each pin to its project's newest cloud image (`scripts/refresh-pins.sh`)
and opens one pull request, and notes a new Fedora or Alpine release (a new
line, opened by hand). With the repository variable
`WEEKLY_UBUNTU_RELEASE=1` it also republishes `ubuntu-24.04`. Every build
runs the distro's full upgrade, so a week-old pin still ships the week's
security fixes.

## License

[MIT](LICENSE). The software installed in the images keeps its own licenses.
