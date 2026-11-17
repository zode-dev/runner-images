#!/usr/bin/env bash
# zode/android: AOSP for x86_64 in a container (redroid), on the Zode base.
# Runs as root in the build VM (the Dockerfile inlines it as one step;
# zoded's make-base.sh EXTRA= runs it after provision.sh for a growable base).
# zoded docs/android.md has the design and the contract.
#
# Leaves behind:
#   - binder_linux.ko for the running kernel, loaded at boot (the kernel
#     variant: only this image has it), binderfs on /dev/binderfs
#   - adb (Ubuntu's, built from AOSP source) and scrcpy (Apache-2.0)
#   - Temurin 21 and the Android SDK (platforms 35/36, build-tools 35/36,
#     platform-tools) at /usr/local/lib/android/sdk for ./gradlew assembleDebug
#   - Docker container zode-android: redroid pinned by digest, booted,
#     unlocked, awake, animations off
#   - /etc/zode/android.json: what zode-desktop reads to serve the phone
#   - the desktop switched on, so the image is frozen with the screen up
set -euxo pipefail

# The build VM's own unattended-upgrades can hold the apt lock (the first
# release, 17 Nov 2026, timed out on it): every apt call waits for the lock
# instead of failing. Kept in the image, where it only makes apt patient.
printf 'DPkg::Lock::Timeout "600";\n' > /etc/apt/apt.conf.d/90zode-lock-timeout
# Waiting is not enough on the official-release path: the step then sat
# behind unattended-upgrades for minutes and the build VM's agent stream
# dropped (17 Nov 2026, runs 44058966673 and 44059730392). Stop the apt
# timers and unattended-upgrades for good, as ci-ubuntu-24.04 does, and wait
# for a run already going. A phone image has no use for them.
systemctl stop apt-daily.timer apt-daily-upgrade.timer apt-daily.service apt-daily-upgrade.service \
  unattended-upgrades.service 2>/dev/null || true
systemctl mask apt-daily.service apt-daily-upgrade.service apt-daily.timer apt-daily-upgrade.timer \
  unattended-upgrades.service
for _ in $(seq 300); do pgrep -x 'apt-get|apt|unattended-upgr|dpkg' >/dev/null || break; sleep 2; done

# Android 15 (redroid 15.0.0-250627, x86_64 + x86). Android 16 (16.0.0-250627,
# sha256:d89f5204...) was tried on 17 Nov 2026 and does not boot with software
# rendering: SurfaceFlinger aborts in primeShaderCache ("output buffer not gpu
# writeable") and the system server loops. Revisit with the next redroid 16.
REDROID_TAG="${REDROID_TAG:-15.0.0-250627}"
REDROID_DIGEST="${REDROID_DIGEST:-sha256:81889852444606824d33eb0232fa5813bce3f0993afe871785120af0d7c991ad}"
SCRCPY_VERSION="${SCRCPY_VERSION:-5.0.1}"
SCRCPY_SHA256="${SCRCPY_SHA256:-9f969d30cc574816077edecda65719c1c70b0aee1df1ba5fa00779ac07b8fd6e}"
WIDTH=720 HEIGHT=1280 DPI=320
SERIAL=127.0.0.1:5555
# Building apps here: Temurin 21 and the Android SDK at GitHub's path (the
# same pins as ci-ubuntu-24.04), with what ./gradlew assembleDebug needs for
# a compileSdk 35 or 36 app.
TEMURIN_21_VERSION="${TEMURIN_21_VERSION:-21.0.13+9}"
TEMURIN_21_SHA256="${TEMURIN_21_SHA256:-d7f5d5cf865a2902b70ff549b97586a7d3f234e016f041ab447ea740c7d66d1c}"
SDK_CMDLINE_TOOLS="${SDK_CMDLINE_TOOLS:-commandlinetools-linux-11076708_latest.zip}"
SDK_CMDLINE_TOOLS_SHA256="${SDK_CMDLINE_TOOLS_SHA256:-2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258}"
SDK=/usr/local/lib/android/sdk
JDK=/usr/lib/jvm/temurin-21-jdk-amd64

retry() { local i; for i in 1 2 3 4 5 6; do "$@" && return 0; sleep $((i * 5)); done; return 1; }

# --- 1. Kernel variant: binder + binderfs -------------------------------------
KVER=$(uname -r)
grep -E 'CONFIG_ANDROID_BINDER(_IPC|FS|_DEVICES)=' "/boot/config-$KVER" || true
if ! modinfo binder_linux >/dev/null 2>&1; then
  retry apt-get update
  tmp=$(mktemp -d)
  (cd "$tmp" && retry apt-get download "linux-modules-extra-$KVER")
  dpkg-deb -x "$tmp"/linux-modules-extra-*.deb "$tmp/x"
  ko=$(find "$tmp/x" -name 'binder_linux.ko*' | head -1)
  [ -n "$ko" ] || { echo "linux-modules-extra-$KVER has no binder_linux"; exit 1; }
  install -D -m0644 "$ko" "/lib/modules/$KVER/updates/zode/$(basename "$ko")"
  rm -rf "$tmp"
  depmod -a "$KVER"
fi
echo binder_linux > /etc/modules-load.d/zode-android.conf
echo 'options binder_linux devices=binder,hwbinder,vndbinder' > /etc/modprobe.d/zode-android.conf
modprobe binder_linux devices=binder,hwbinder,vndbinder
mkdir -p /dev/binderfs
grep -q ' /dev/binderfs ' /proc/mounts || mount -t binder binder /dev/binderfs
cat > /etc/systemd/system/dev-binderfs.mount <<'UNIT'
[Unit]
Description=binderfs for Android (zode/android)
After=systemd-modules-load.service
Before=docker.service
[Mount]
What=binder
Where=/dev/binderfs
Type=binder
[Install]
WantedBy=local-fs.target
UNIT
systemctl daemon-reload
systemctl enable dev-binderfs.mount
ls -l /dev/binderfs

# --- 2. adb and scrcpy -------------------------------------------------------
retry apt-get update
DEBIAN_FRONTEND=noninteractive retry apt-get install -y --no-install-recommends adb x11-utils
curl -fsSL --retry 6 --retry-delay 5 --retry-all-errors --connect-timeout 20 -o /tmp/scrcpy.tgz \
  "https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}/scrcpy-linux-x86_64-v${SCRCPY_VERSION}.tar.gz"
echo "$SCRCPY_SHA256  /tmp/scrcpy.tgz" | sha256sum -c -
rm -rf /opt/scrcpy && mkdir -p /opt/scrcpy
tar -xzf /tmp/scrcpy.tgz -C /opt/scrcpy --strip-components=1
rm -f /tmp/scrcpy.tgz /opt/scrcpy/adb   # Ubuntu's adb, not Google's platform-tools binary
cat > /usr/local/bin/scrcpy <<'SH'
#!/bin/sh
export ADB=/usr/bin/adb SCRCPY_SERVER_PATH=/opt/scrcpy/scrcpy-server
exec /opt/scrcpy/scrcpy_bin "$@"
SH
[ -x /opt/scrcpy/scrcpy_bin ] || mv /opt/scrcpy/scrcpy /opt/scrcpy/scrcpy_bin
chmod 0755 /usr/local/bin/scrcpy
scrcpy --version

# --- 2b. JDK and Android SDK for building apps -------------------------------
dl() { curl -fsSL --retry 6 --retry-delay 5 --retry-all-errors --connect-timeout 20 -o "$2" "$1"; }
v=$TEMURIN_21_VERSION
dl "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${v//+/%2B}/OpenJDK21U-jdk_x64_linux_hotspot_${v/+/_}.tar.gz" /tmp/jdk.tar.gz
echo "$TEMURIN_21_SHA256  /tmp/jdk.tar.gz" | sha256sum -c -
rm -rf "$JDK" && mkdir -p "$JDK"
tar -xzf /tmp/jdk.tar.gz -C "$JDK" --strip-components=1
rm -f /tmp/jdk.tar.gz
for b in java javac jar keytool; do ln -sf "$JDK/bin/$b" "/usr/local/bin/$b"; done
"$JDK/bin/java" -version 2>&1 | grep "\"${v%+*}\"" >/dev/null

dl "https://dl.google.com/android/repository/$SDK_CMDLINE_TOOLS" /tmp/cmdline-tools.zip
echo "$SDK_CMDLINE_TOOLS_SHA256  /tmp/cmdline-tools.zip" | sha256sum -c -
rm -rf "$SDK/cmdline-tools/latest" /tmp/cmdline-tools && mkdir -p "$SDK/cmdline-tools"
unzip -q /tmp/cmdline-tools.zip -d /tmp
mv /tmp/cmdline-tools "$SDK/cmdline-tools/latest"
rm -f /tmp/cmdline-tools.zip
sdkm() { JAVA_HOME=$JDK "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" "$@" < <(yes); }
sdkm --licenses >/dev/null
pkgs=("platforms;android-35" "platforms;android-36" "build-tools;35.0.0" "build-tools;36.0.0" "platform-tools")
for i in 1 2 3; do sdkm --install "${pkgs[@]}" >/tmp/sdkmanager.log 2>&1 && break; tail -20 /tmp/sdkmanager.log; sleep $((i * 15)); done
for p in "${pkgs[@]}"; do
  [ -f "$SDK/${p//;//}/source.properties" ] || { echo "missing $p" >&2; exit 1; }
done
# One adb on the box: two adb versions kill each other's server, and the
# phone's screen (scrcpy) and zode-desktop talk to Ubuntu's.
ln -sf /usr/bin/adb "$SDK/platform-tools/adb"
rm -rf /tmp/sdkmanager.log /root/.android/cache "$SDK/.temp"
chmod -R a+rwX /usr/local/lib/android
cat > /etc/profile.d/zode-android-sdk.sh <<PROFILE
export JAVA_HOME=$JDK ANDROID_HOME=$SDK ANDROID_SDK_ROOT=$SDK
PROFILE
for kv in "JAVA_HOME=$JDK" "ANDROID_HOME=$SDK" "ANDROID_SDK_ROOT=$SDK"; do
  sed -i "/^${kv%%=*}=/d" /etc/environment
  echo "$kv" >> /etc/environment
done

# --- 3. Android ---------------------------------------------------------------
systemctl enable --now docker
retry docker pull -q "redroid/redroid:${REDROID_TAG}@${REDROID_DIGEST}"
docker rm -f zode-android 2>/dev/null || true
docker run -d --name zode-android --restart unless-stopped --privileged \
  -p 127.0.0.1:5555:5555 -v zode-android-data:/data \
  "redroid/redroid:${REDROID_TAG}@${REDROID_DIGEST}" \
  androidboot.redroid_width=$WIDTH androidboot.redroid_height=$HEIGHT \
  androidboot.redroid_dpi=$DPI androidboot.redroid_fps=30 \
  androidboot.redroid_gpu_mode=guest androidboot.use_memfd=true \
  ro.product.cpu.abilist=x86_64,x86 ro.product.cpu.abilist64=x86_64 ro.product.cpu.abilist32=x86 \
  ro.vendor.product.cpu.abilist=x86_64,x86 ro.vendor.product.cpu.abilist64=x86_64 ro.vendor.product.cpu.abilist32=x86 \
  ro.dalvik.vm.native.bridge=0 ro.enable.native.bridge.exec=0
# The image announces ARM ABIs through a native-bridge stub (libnb.so) but
# ships no translation library; the properties above make Android itself
# refuse ARM-only apps instead of installing apps that cannot start.

booted=0
for i in $(seq 1 180); do
  adb connect "$SERIAL" >/dev/null 2>&1 || true
  if [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then booted=1; break; fi
  sleep 2
done
if [ "$booted" != 1 ]; then docker logs --tail 80 zode-android || true; dmesg | tail -40; echo "Android did not boot"; exit 1; fi
sh_() { adb -s "$SERIAL" shell "$@"; }
# Agents and screenshots want a still, awake, unlocked phone.
sh_ settings put global window_animation_scale 0
sh_ settings put global transition_animation_scale 0
sh_ settings put global animator_duration_scale 0
sh_ settings put system screen_off_timeout 2147483647
sh_ settings put global stay_on_while_plugged_in 7
sh_ settings put system accelerometer_rotation 0
sh_ wm fixed-to-user-rotation enabled   # rotate turns every app, the launcher too
sh_ settings put system user_rotation 0
sh_ locksettings set-disabled true || true
sh_ svc power stayon true || true
sh_ input keyevent KEYCODE_WAKEUP
sh_ wm dismiss-keyguard || true
sh_ input keyevent KEYCODE_HOME
RELEASE=$(sh_ getprop ro.build.version.release | tr -d '\r')
SDK=$(sh_ getprop ro.build.version.sdk | tr -d '\r')
ABIS=$(sh_ getprop ro.product.cpu.abilist | tr -d '\r')

install -d /etc/zode
cat > /etc/zode/android.json <<JSON
{"serial":"$SERIAL","container":"zode-android","width":$WIDTH,"height":$HEIGHT,"density":$DPI,
 "release":"$RELEASE","sdk":$SDK,"abis":"$ABIS","redroid":"redroid/redroid:${REDROID_TAG}@${REDROID_DIGEST}",
 "scrcpy":"$SCRCPY_VERSION"}
JSON
cat /etc/zode/android.json

install -d /usr/share/doc/zode-android
cat > /usr/share/doc/zode-android/NOTICE <<NOTICE
zode/android ships:
- redroid/redroid:${REDROID_TAG}@${REDROID_DIGEST}: AOSP $RELEASE for x86_64/x86
  built for containers (https://github.com/remote-android/redroid-doc), Apache-2.0
  with the licences of the AOSP components it contains. No Google apps, no Google
  Play, no ARM translation.
- scrcpy $SCRCPY_VERSION (https://github.com/Genymobile/scrcpy), Apache-2.0; its
  static build links FFmpeg (LGPL-2.1-or-later) and SDL (zlib).
- adb from Ubuntu's adb package (AOSP source, Apache-2.0).
- binder_linux.ko from Ubuntu's linux-modules-extra-$KVER, GPL-2.0.
- Eclipse Temurin $TEMURIN_21_VERSION (https://adoptium.net), GPL-2.0 with the
  Classpath Exception.
- The Android SDK command-line tools, platforms, build-tools and platform-tools
  under $SDK, from Google under the Android Software Development Kit License
  Agreement, accepted at build time (sdkmanager --licenses), as on GitHub's
  runner images. platform-tools/adb points at Ubuntu's adb.
NOTICE

# --- 4. The screen up before the freeze ---------------------------------------
# zode-desktop serves the phone when /etc/zode/android.json exists; switching
# the desktop on here keeps Xvfb, scrcpy and voxl running in the snapshot.
# A node whose zode-desktop predates the phone (no `android` verb) skips
# this: the screen then comes up on the first `zode desktop` instead of
# being frozen up, which only costs start time.
H=/usr/local/lib/zode/zode-desktop
helper_usage=$( { [ -x "$H" ] && "$H" 2>&1; } || true)
if [[ "$helper_usage" == *"android VERB"* ]]; then
  "$H" enable desktop
  "$H" android status
else
  echo "zode-desktop here has no android support; the screen starts on first use"
fi
# Warm the pages a new sandbox touches first.
cat /opt/scrcpy/* /usr/bin/adb >/dev/null 2>&1 || true
