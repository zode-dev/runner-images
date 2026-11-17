# android

Use it with `zode/android`. Not released yet (`HOLD`).

Android (AOSP for x86_64 and x86, redroid) running in a container on the Zode
base, with its screen on the sandbox's desktop. No Google Play, no ARM
translation: ARM-only apks are refused at install.

```sh
zode new phone --image zode/android --desktop
zode android phone install app.apk --launch
zode desktop phone screenshot -o shot.png
zode android phone key back
```

Setup: [`setup.sh`](setup.sh) (inlined into the Dockerfile by
`scripts/render.sh`). Design, API and licences: zode-dev/zoded
`docs/android.md`.

The software list is written by the publish workflow after the first release.
