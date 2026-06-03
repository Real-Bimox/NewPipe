#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

IMAGE=${NEWPIPE_ANDROID_BUILDER_IMAGE:-docker.io/cimg/android:2025.12}
CONTAINER_NAME=${NEWPIPE_ANDROID_CONTAINER_NAME:-newpipe-android-build-$$}
GRADLE_CACHE=${NEWPIPE_GRADLE_CACHE:-"$HOME/.cache/newpipe-waydroid/gradle"}
ANDROID_CACHE=${NEWPIPE_ANDROID_CACHE:-"$HOME/.cache/newpipe-waydroid/android"}
APK_PATH="$REPO_ROOT/app/build/outputs/apk/debug/app-debug.apk"

if ! command -v podman >/dev/null 2>&1; then
    echo "podman is required but was not found on PATH." >&2
    exit 1
fi

mkdir -p "$GRADLE_CACHE" "$ANDROID_CACHE"

GRADLE_ARGS=("$@")
if [ "${#GRADLE_ARGS[@]}" -eq 0 ]; then
    GRADLE_ARGS=(assembleDebug --stacktrace -DskipFormatKtlint)
fi

echo "Building NewPipe debug APK with $IMAGE"
echo "Repository: $REPO_ROOT"
echo "Gradle args: ${GRADLE_ARGS[*]}"

podman run --rm \
    --name "$CONTAINER_NAME" \
    --user root \
    --memory 8g \
    --cpus 8 \
    -e HOME=/tmp/newpipe-home \
    -e GRADLE_USER_HOME=/tmp/gradle \
    -v "$REPO_ROOT:/workspace:Z" \
    -v "$GRADLE_CACHE:/tmp/gradle:Z" \
    -v "$ANDROID_CACHE:/tmp/android-cache:Z" \
    -w /workspace \
    "$IMAGE" \
    bash -lc '
        set -euo pipefail
        mkdir -p "$HOME" "$GRADLE_USER_HOME" /tmp/android-cache

        SDKMANAGER=$(command -v sdkmanager || true)
        if [ -z "$SDKMANAGER" ] && [ -n "${ANDROID_HOME:-}" ]; then
            SDKMANAGER=$(find "$ANDROID_HOME" -type f -name sdkmanager | head -n 1 || true)
        fi
        if [ -z "$SDKMANAGER" ]; then
            echo "sdkmanager was not found in the Android builder image." >&2
            exit 1
        fi

        yes | "$SDKMANAGER" --licenses >/dev/null || true

        if [ -n "${ANDROID_HOME:-}" ] && [ ! -d "$ANDROID_HOME/platforms/android-36.1" ]; then
            "$SDKMANAGER" --install "platforms;android-36.1"
        fi

        if [ -n "${ANDROID_HOME:-}" ] && ! ls "$ANDROID_HOME"/build-tools/36.1.* >/dev/null 2>&1; then
            "$SDKMANAGER" --install "build-tools;36.1.0" \
                || "$SDKMANAGER" --install "build-tools;36.1.0-rc1"
        fi

        ./gradlew "$@"
    ' bash "${GRADLE_ARGS[@]}"

if [ ! -f "$APK_PATH" ]; then
    echo "Build completed but APK was not found at $APK_PATH" >&2
    exit 1
fi

echo "Built APK: $APK_PATH"
