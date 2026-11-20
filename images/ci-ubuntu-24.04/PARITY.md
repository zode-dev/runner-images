# ci-ubuntu-24.04 compared with GitHub's ubuntu-24.04

Zode `ci-ubuntu-24.04` 20261120.36 against GitHub `ubuntu24/20261116.376`, from both images' own
software reports. Written by `scripts/parity.sh` with every release; do not
edit it by hand. Why something is left out: `images/ci-ubuntu-24.04/parity.tsv`.

| | Count |
| --- | --- |
| Same | 143 |
| Different version | 26 |
| Missing on Zode | 48 |
| Only on Zode | 24 |

## Missing on Zode

| Area | Section | Name | GitHub | Why |
| --- | --- | --- | --- | --- |
| Tool cache | Cached Tools | PyPy | 3.9.19 [PyPy 7.3.16], 3.10.16 [PyPy 7.3.19], 3.11.17 [PyPy 8.0.1] | actions/setup-python downloads it |
| Tool cache | Cached Tools | Ruby | 3.2.11, 3.3.13, 3.4.12, 4.0.9 | ruby/setup-ruby downloads it (prebuilt, seconds) |
| Environment | Environment variables | CONDA | /usr/share/miniconda | no Miniconda |
| Environment | Environment variables | EDGEWEBDRIVER | /usr/local/share/edge_driver | no Edge |
| Environment | Environment variables | VCPKG_INSTALLATION_ROOT | /usr/local/share/vcpkg | no vcpkg |
| Software | .NET Tools | .NET Core SDK | 8.0.134, 8.0.206, 8.0.319, 8.0.428, 9.0.124, 9.0.205, 9.0.321, 10.0.115, 10.0.204, 10.0.303, 10.0.404, 11.0.100 | large toolchain: actions/setup-dotnet installs it, or use a workspace image |
| Software | .NET Tools | nbgv | 3.10.94+dea9a6c17c | .NET tool: dotnet tool install |
| Software | Browsers and Drivers | Chromium | 157.0.8103.0 | Playwright's Chromium is in /ms-playwright |
| Software | Browsers and Drivers | Microsoft Edge | 157.0.4341.60 | not added: Chrome, Firefox and Playwright cover browser tests |
| Software | Browsers and Drivers | Microsoft Edge WebDriver | 157.0.4341.60 | no Edge |
| Software | CLI Tools | AWS SAM CLI | 1.172.1 | aws-actions/setup-sam installs it |
| Software | CLI Tools | Azure CLI (azure-devops) | 1.0.11 | az extension add --name azure-devops |
| Software | Haskell Tools | Cabal | 3.18.2.0 | large toolchain: haskell-actions/setup installs it |
| Software | Haskell Tools | GHC | 9.14.1 | large toolchain: haskell-actions/setup installs it |
| Software | Haskell Tools | GHCup | 0.2.6.2 | large toolchain: haskell-actions/setup installs it |
| Software | Haskell Tools | Stack | 3.11.1 | large toolchain: haskell-actions/setup installs it |
| Software | Language and Runtime | Julia | 1.13.4 | julia-actions/setup-julia installs it |
| Software | Language and Runtime | Kotlin | 2.4.21 | the Gradle and Maven plugins fetch it |
| Software | Language and Runtime | Swift | 6.4.2 | large toolchain: swift-actions/setup-swift installs it |
| Software | Operating system | Image Version | 20261116.376.1 | in the ImageVersion variable |
| Software | PHP Tools | Composer | 2.11.2 | shivammathur/setup-php installs it |
| Software | PHP Tools | PHP | 8.3.6 | shivammathur/setup-php installs it |
| Software | PHP Tools | PHPUnit | 8.5.57 | shivammathur/setup-php installs it |
| Software | Package Management | Homebrew | 7.0.14 | not on PATH on GitHub either; install it in a step |
| Software | Package Management | Miniconda | 26.9.4 | conda-incubator/setup-miniconda installs it |
| Software | Package Management | Vcpkg | (build from commit 1c6c7f95b0) | lukka/run-vcpkg clones it |
| Software | Package Management | cpan | 1.64 | comes with Perl; cpanminus is one apt package away |
| Software | PowerShell Modules | Az | 15.6.1 | PowerShell module: Install-Module in a step |
| Software | PowerShell Modules | Microsoft.Graph | 2.41.2 | PowerShell module: Install-Module in a step |
| Software | PowerShell Modules | PSScriptAnalyzer | 1.25.0 | PowerShell module: Install-Module in a step |
| Software | PowerShell Modules | Pester | 5.9.0 | PowerShell module: Install-Module in a step |
| Software | Project Management | Lerna | 10.1.1 | npx lerna |
| Software | Tools | AzCopy | 10.34.1 - available by `azcopy` and `azcopy10` aliases | not added yet: download in a step |
| Software | Tools | Bazel | 9.3.2 | `bazel` is Bazelisk, which fetches the version a repository pins |
| Software | Tools | Bicep | 0.49.2 | az bicep install |
| Software | Tools | CodeQL Action Bundle | 2.27.4 | github/codeql-action downloads the bundle its own version pins |
| Software | Tools | Docker Amazon ECR Credential Helper | 0.13.0 | aws-actions/amazon-ecr-login covers it |
| Software | Tools | Fastlane | 2.242.0 | a Ruby gem: gem install fastlane |
| Software | Tools | Git-ftp | 1.6.0 | not added |
| Software | Tools | Minikube | 1.39.0 | medyagh/setup-minikube installs it; kind is here |
| Software | Tools | Newman | 6.2.3 | npx newman |
| Software | Tools | Packer | 1.16.2 | hashicorp/setup-packer installs it |
| Software | Tools | Parcel | 2.16.4 | npx parcel |
| Software | Tools | Pulumi | 3.276.0 | pulumi/actions installs it |
| Software | Tools | n | 11.0.0 | actions/setup-node covers it |
| Software | Tools | nvm | 0.41.0 | actions/setup-node covers it |
| Software | Web Servers | apache2 | 2.4.58 | web servers: apt-get install in a step |
| Software | Web Servers | nginx | 1.24.0 | web servers: apt-get install in a step |

Every apt package GitHub lists is installed.

## Different versions

| Area | Name | GitHub | Zode |
| --- | --- | --- | --- |
| Tool cache | Go | 1.25.14, 1.26.11, 1.27.4 | 1.24.13, 1.25.14, 1.26.11 (missing 1.27) |
| Software | AWS CLI | 2.40.4 | 2.40.1 |
| Software | Android SDK Platform-Tools | 37.0.1 | 37.0.3 |
| Software | Azure CLI | 2.93.0 | 2.92.0 |
| Software | CMake | 3.31.6 | 3.28.3 |
| Software | ChromeDriver | 157.0.8103.78 | 157.0.8103.38 |
| Software | Clang | 16.0.6, 17.0.6, 18.1.3 | 18.1.3 (missing 16.0.6, 17.0.6) |
| Software | Clang-format | 16.0.6, 17.0.6, 18.1.3 | 18.1.3 (missing 16.0.6, 17.0.6) |
| Software | Clang-tidy | 16.0.6, 17.0.6, 18.1.3 | 18.1.3 (missing 16.0.6, 17.0.6) |
| Software | Docker Client | 28.0.4 | 29.1.3 |
| Software | Docker Compose | 2.38.2 | 2.40.3 |
| Software | Docker Server | 28.0.4 | 29.1.3 |
| Software | Docker-Buildx | 0.39.0 | 0.30.1 |
| Software | GNU C++ | 12.4.0, 13.3.0, 14.2.0 | 13.3.0 (missing 12.4.0, 14.2.0) |
| Software | GNU Fortran | 12.4.0, 13.3.0, 14.2.0 | 13.3.0 (missing 12.4.0, 14.2.0) |
| Software | Git | 2.56.1 | 2.43.0 |
| Software | Git LFS | 3.8.1 | 3.4.1 |
| Software | GitHub CLI | 2.104.0 | 2.103.3 |
| Software | Google Chrome | 157.0.8103.78 | 157.0.8103.38 |
| Software | Kernel Version | 7.0.0-1017-azure | 6.8.0-147-generic |
| Software | Maven | 3.10.1 | 3.10.0 |
| Software | Ninja | 1.13.2 | 1.11.1 |
| Software | Node.js | 22.23.5 | 22.23.4 |
| Software | Pipx | 1.16.7 | 1.4.3 |
| Software | PostgreSQL | 16.16 | 16.15, stopped |
| Software | zstd | 1.5.7 | 1.5.5 |

## Only on Zode

Go 1.24.13, pnpm 12.21.0, Bun 1.4.5, GitHub Actions runner 2.338.2, rsync 3.2.7, OpenSSH 9.6, curl 8.5.0, ShellCheck 0.9.0, Redis 7.0.15, stopped, Playwright 1.65.0, Java (Temurin) 8.0.512-9, 11.0.33-10, 17.0.21-9, 21.0.13-9, 25.0.5-8, ImageOS ubuntu24, JAVA_HOME /usr/lib/jvm/temurin-17-jdk-amd64, CARGO_HOME /home/runner/.cargo, ACCEPT_EULA Y, CHROME_PATH /usr/bin/google-chrome, RUSTUP_HOME /home/runner/.rustup, ImageVersion 20261120.36, GOROOT_1_24_X64 /opt/hostedtoolcache/go/1.24.13/x64, GOROOT_1_25_X64 /opt/hostedtoolcache/go/1.25.14/x64, GOROOT_1_26_X64 /opt/hostedtoolcache/go/1.26.11/x64, RUNNER_TOOL_CACHE /opt/hostedtoolcache, AGENT_TOOLSDIRECTORY /opt/hostedtoolcache, PLAYWRIGHT_BROWSERS_PATH /ms-playwright.

<details><summary>Same on both (143)</summary>

Node.js, Python, ANDROID_HOME, ANDROID_NDK, ANDROID_NDK_HOME, ANDROID_NDK_LATEST_HOME, ANDROID_NDK_ROOT, ANDROID_SDK_ROOT, CHROMEWEBDRIVER, GECKOWEBDRIVER, JAVA_HOME_11_X64, JAVA_HOME_17_X64, JAVA_HOME_21_X64, JAVA_HOME_25_X64, JAVA_HOME_8_X64, SELENIUM_JAR_PATH, AWS CLI Session Manager Plugin, Android CMake, Android Command Line Tools, Android Google Play services, Android Google Repository, Android NDK, Android SDK Build-tools, Android SDK Platforms, Android Support Repository, Ansible, Ant, Bash, Bazelisk, Buildah, Cargo, Dash, Geckodriver, Google Cloud CLI, Gradle, Haveged, Helm, Java, Kind, Kubectl, Kustomize, MediaInfo, Mercurial, Mozilla Firefox, MySQL, Npm, OS Version, OpenSSL, Perl, Pip, Pip3, Podman, PowerShell, Python, Ruby, RubyGems, Rust, Rustdoc, Rustfmt, Rustup, Selenium server, Skopeo, Sphinx Open Source Search Server, Systemd version, Yarn, jq, sqlite3, yamllint, yq.

apt packages: acl, aria2, autoconf, automake, binutils, bison, brotli, bzip2, coreutils, curl, dbus, dnsutils, dpkg, dpkg-dev, fakeroot, file, findutils, flex, fonts-noto-color-emoji, ftp, g++, gcc, gnupg2, haveged, iproute2, iputils-ping, jq, libicu-dev, libnss3-tools, libsqlite3-dev, libssl-dev, libtool, libyaml-dev, locales, lz4, m4, make, mediainfo, mercurial, net-tools, netcat, openssh-client, p7zip-full, p7zip-rar, parallel, patchelf, pigz, pkg-config, pollinate, python-is-python3, rpm, rsync, shellcheck, sphinxsearch, sqlite3, ssh, sshpass, sudo, swig, systemd-coredump, tar, telnet, texinfo, time, tk, tree, tzdata, unzip, upx, wget, xvfb, xz-utils, zip, zsync.

</details>
