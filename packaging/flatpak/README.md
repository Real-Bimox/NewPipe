# NewPipe Flatpak — fixed local build

This directory builds a **working** Flatpak of NewPipe (the Android app running
under [android-translation-layer](https://gitlab.com/android_translation_layer/android_translation_layer),
ATL) from the Flathub manifests plus two local patches. It replaces the
crashing Flathub build (`net.newpipe.NewPipe` "unofficial port") with one that
survives video playback on hosts with broken VA-API drivers (e.g. proprietary
NVIDIA).

Verified working 2026-09-13 on Bazzite 44 (Fedora Kinoite, KDE, NVIDIA
595.71.05): startup, feed load, and video playback with audio and video.

## What was broken

Two independent bugs, both in the ATL stack (not in NewPipe itself):

1. **SIGSEGV during playback / feed load — use-after-free of native ICU
   `RegexPattern`.** The runtime's reference processing runs
   `sun.misc.Cleaner` instances while their referents are still strongly
   reachable. `java.util.regex.Pattern` registers its native ICU object with
   a cleaner via `libcore.util.NativeAllocationRegistry`; the cleaner deletes
   it early, and the next `Pattern.matcher()` dereferences freed memory
   (confirmed by gdb on three coredumps: the dangling handle pointed into a
   recycled heap chunk containing ART's own crash-message string; faulting
   instruction `mov 0xef8(%rax),%rsi` with `rax = 0`). NewPipeExtractor's
   regex-heavy parsing on ExoPlayer's loader thread hits this within seconds.
2. **No video frames on NVIDIA hosts.** ATL's `MediaCodec` implementation
   selects VA-API/DRM_PRIME hardware decoding, but the VA driver on
   proprietary NVIDIA hosts cannot allocate surfaces (`AVHWFramesContext:
   Failed to create surface`, `hardware accelerator failed to decode
   picture`), so every picture fails and nothing is ever rendered.

Full evidence writeup for filing upstream: `UPSTREAM-ISSUE-DRAFT.md`.

## The fixes

- `patches/0001-art-standalone-no-cleaner-free.patch` (against
  `art_standalone` @ `66a5d9079b159e9c5819bfeef4a6fff6a5f32719`):
  `NativeAllocationRegistry.registerNativeAllocation(Object, long)` no longer
  creates a `sun.misc.Cleaner`. Cleaner-managed native allocations are
  deliberately kept alive for the process lifetime (bounded leak, typically
  tens of MB per session); the returned explicit-free `Runnable` still frees
  exactly once. This removes the use-after-free entirely.
- `patches/0002-atl-env-gated-hw-decode.patch` (against
  `android_translation_layer` @ `923b6df1c56a9100a8c1bc4262ca963af37b69bf`):
  `MediaCodec.native_configure_video` honors `ATL_DISABLE_HW_DECODE`; when
  set, VA-API/DRM_PRIME selection is skipped and decoding falls back to
  software, rendering reliably through the swscale path. `newpipe.sh` exports
  it, so the packaged app always uses software video decode.

Trade-offs: native memory for regex patterns/matchers accumulates for the
session instead of being freed (small, bounded); video decoding uses the CPU
(trivial at 1080p on modern hardware). Both are strictly better than the
crashes they replace.

## Building on another Linux system

Requirements: a distribution with Flatpak (user install is sufficient — no
root needed), network access, and roughly 10 GB of free disk for SDKs and
build trees.

```bash
# One-time setup
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user --noninteractive flathub org.gnome.Sdk//50
flatpak install --user --noninteractive flathub org.freedesktop.Sdk.Extension.openjdk17//25.08
# flatpak-builder itself is a Flatpak:
flatpak install --user --noninteractive flathub org.flatpak.Builder

cd packaging/flatpak

# 1. Build the (patched) ATL BaseApp — installs as branch "master", user install.
#    This is the long step: it compiles ART (art_standalone). Expect 20-60 min
#    depending on CPU.
flatpak run org.flatpak.Builder --user --install --force-clean \
    build-base io.gitlab.android_translation_layer.BaseApp.yml

# 2. Build NewPipe on top of it — installs as branch "stable", replacing any
#    Flathub copy in the *user* installation. Fast (APK download + dex2oat).
flatpak run org.flatpak.Builder --user --install --force-clean \
    build-app net.newpipe.NewPipe.yml
```

Notes on the branch layout (these matter):

- `net.newpipe.NewPipe.yml` sets `base-version: master` because the locally
  built BaseApp installs on its `master` branch (the Flathub `stable` BaseApp
  is the *unpatched* one — building against it silently produces a broken
  app).
- `net.newpipe.NewPipe.yml` sets `branch: stable` so the result replaces the
  broken Flathub build and the desktop launcher entry points at it.
- The app needs the GNOME 50 Platform runtime at runtime (auto-installed as a
  dependency).

## Running

```bash
flatpak run net.newpipe.NewPipe
```

or launch "NewPipe" from the desktop. If the launcher does not pick the entry
up after the install (KDE menu cache can lag), either log out/in once, or:

```bash
mkdir -p ~/.local/share/applications
cp ~/.local/share/flatpak/exports/share/applications/net.newpipe.NewPipe.desktop \
   ~/.local/share/applications/
kbuildsycoca6   # KDE only; GNOME picks it up on its own
```

App data lives in `~/.var/app/net.newpipe.NewPipe/` (survives rebuilds).

## Tuning

- **Intel/AMD graphics with a working VA driver:** hardware video decode can
  be re-enabled by removing the `export ATL_DISABLE_HW_DECODE=1` line from
  `newpipe.sh` and rebuilding only the app (step 2 above). The crash fix
  (patch 0001) is independent of this.
- **Updating NewPipe:** bump the APK `url`/`sha256` in
  `net.newpipe.NewPipe.yml` (current release assets:
  https://archive.newpipe.net/fdroid/repo/) and re-run step 2.

## Restoring the Flathub original

```bash
flatpak install --user --from flathub net.newpipe.NewPipe
```

(Only do this once the upstream bugs are fixed; the Flathub build crashes on
playback on NVIDIA hosts as of 2026-09-13.)

## Upstreaming

Both patches are MR-ready (generated with `git format-patch` against the
exact commits pinned in the BaseApp manifest). The intended targets:

- `0001` → https://gitlab.com/android_translation_layer/art_standalone
- `0002` → https://gitlab.com/android_translation_layer/android_translation_layer

Flathub's app page routes this Flatpak's bugs to the ATL issue tracker;
`UPSTREAM-ISSUE-DRAFT.md` contains the writeup with the gdb evidence.
