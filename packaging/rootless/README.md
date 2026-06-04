# NewPipe Rootless Packaging

Rootless tooling version: 0.1.0

This directory keeps local rootless build tooling for this NewPipe checkout.
It deliberately does not provide a Waydroid launcher or any other root-managed
runtime integration.

## What This Provides

- `build-debug-apk-in-podman.sh` builds `app-debug.apk` in a rootless Podman
  Android build container.
- The build container runs as the current host UID/GID, not as container root.
- Android SDK and Gradle caches live under:

```text
~/.cache/newpipe-rootless/android-sdk
~/.cache/newpipe-rootless/gradle
```

The expected APK path is:

```text
app/build/outputs/apk/debug/app-debug.apk
```

## Build

From the repository root:

```bash
packaging/rootless/build-debug-apk-in-podman.sh
```

By default the script uses the already-tested builder image:

```text
docker.io/cimg/android:2025.12
```

Override it when needed:

```bash
NEWPIPE_ANDROID_BUILDER_IMAGE=docker.io/cimg/android:2026.01 \
  packaging/rootless/build-debug-apk-in-podman.sh
```

Pass Gradle tasks after the script name:

```bash
packaging/rootless/build-debug-apk-in-podman.sh testDebugUnitTest --stacktrace
```

## Runtime Status

There is currently no verified rootless playback runtime for this checkout on
this host.

Tested rootless options:

- `desktopApp` Gradle task discovery succeeds, but the current Compose desktop
  app renders an empty shell and does not provide NewPipe playback.
- Android Emulator 36.2.12 in rootless Podman can access `/dev/kvm`, but both
  default AOSP and AOSP ATD x86_64 images segfault before boot.
- Android Emulator 36.2.12 copied to `/tmp` and run directly as the host user
  also segfaults before boot. Running without KVM survives briefly, then
  segfaults before Android reaches boot completion.

Waydroid was removed from this local packaging path because it uses a
root-managed Android LXC container. That does not satisfy an absolute-rootless
runtime requirement.

## Future NewPipe Updates

1. Pull or merge the newer NewPipe code.
2. Re-run `packaging/rootless/build-debug-apk-in-podman.sh`.
3. Use the APK on a real Android device or another verified rootless runtime.

