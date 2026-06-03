# NewPipe Waydroid launcher

Wrapper version: 0.1.0

This directory keeps the local Bazzite/Waydroid integration for this NewPipe
checkout. It does not modify the upstream Android app code.

## What this provides

- `build-debug-apk-in-podman.sh` builds `app-debug.apk` in a temporary Podman
  Android build container.
- `newpipe-waydroid.sh` installs the built debug APK into Waydroid and launches
  it.
- `install-host-launcher.sh` installs a user desktop entry so NewPipe appears in
  the host application launcher.

The launcher targets the debug package, `org.schabi.newpipe.debug`, which is
produced by `./gradlew assembleDebug`.

## Build

From the repository root:

```bash
packaging/waydroid/build-debug-apk-in-podman.sh
```

The build script uses a one-shot Podman container and bind-mounts this checkout
at `/workspace` with SELinux relabeling. By default it uses:

```text
docker.io/cimg/android:2025.12
```

Override the image when needed:

```bash
NEWPIPE_ANDROID_BUILDER_IMAGE=docker.io/cimg/android:2026.01 \
  packaging/waydroid/build-debug-apk-in-podman.sh
```

The expected APK path is:

```text
app/build/outputs/apk/debug/app-debug.apk
```

## Install the host launcher

```bash
packaging/waydroid/install-host-launcher.sh
```

This writes:

```text
~/.local/bin/newpipe-waydroid
~/.local/share/applications/org.schabi.newpipe.waydroid.desktop
```

## Run

Start NewPipe from the desktop launcher, or run:

```bash
newpipe-waydroid
```

The launcher checks that Waydroid is initialized. If the APK exists, it installs
or updates it before launching `org.schabi.newpipe.debug`.

Waydroid initialization is deliberately not done by these scripts because it is a
host Android runtime setup step, not a repo build step. On Bazzite, initialize it
with:

```bash
ujust configure-waydroid init
```

The equivalent manual command is:

```bash
sudo systemctl enable --now waydroid-container
sudo waydroid init \
  -c 'https://ota.waydro.id/system' \
  -v 'https://ota.waydro.id/vendor'
sudo restorecon -R /var/lib/waydroid
```

Use the default VANILLA image; NewPipe does not need Google apps or Google Play
Services.

The launcher sets `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, and
`WAYLAND_DISPLAY` when they are missing. This matters for non-interactive
launches because `waydroid status` talks to the system bus, while
`waydroid app install` and `waydroid app launch` need the user session bus.

## Future NewPipe updates

1. Pull or merge the newer NewPipe code.
2. Re-run `packaging/waydroid/build-debug-apk-in-podman.sh`.
3. Launch NewPipe normally; the wrapper installs the newer debug APK before
   starting it.
