#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

IMAGE=${NEWPIPE_ANDROID_BUILDER_IMAGE:-docker.io/cimg/android:2025.12}
CONTAINER_NAME=${NEWPIPE_ANDROID_CONTAINER_NAME:-newpipe-rootless-android-build-$$}
CACHE_ROOT=${NEWPIPE_ROOTLESS_CACHE:-"$HOME/.cache/newpipe-rootless"}
GRADLE_CACHE=${NEWPIPE_GRADLE_CACHE:-"$CACHE_ROOT/gradle"}
ANDROID_SDK_CACHE=${NEWPIPE_ANDROID_SDK_CACHE:-"$CACHE_ROOT/android-sdk"}
APK_PATH="$REPO_ROOT/app/build/outputs/apk/debug/app-debug.apk"
HOST_UID=$(id -u)
HOST_GID=$(id -g)
SDK_STAGE=""

if ! command -v podman >/dev/null 2>&1; then
    echo "podman is required but was not found on PATH." >&2
    exit 1
fi

mkdir -p "$GRADLE_CACHE" "$ANDROID_SDK_CACHE"

cleanup_stage() {
    if [ -n "${SDK_STAGE:-}" ]; then
        rm -rf "$SDK_STAGE"
    fi
}

trap cleanup_stage EXIT

stage_android_sdk() {
    if [ -x "$ANDROID_SDK_CACHE/cmdline-tools/latest/bin/sdkmanager" ]; then
        return 0
    fi

    SDK_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/newpipe-sdk-stage.XXXXXX")
    chmod 0777 "$SDK_STAGE"

    echo "Staging Android SDK into $ANDROID_SDK_CACHE"
    podman run --rm \
        --name "$CONTAINER_NAME-sdk" \
        -v "$SDK_STAGE:/out:Z" \
        "$IMAGE" \
        bash -lc '
            set -euo pipefail
            mkdir -p /out/sdk
            cp -r "$ANDROID_HOME"/. /out/sdk/
        '

    cp -r "$SDK_STAGE/sdk"/. "$ANDROID_SDK_CACHE"/
    chmod -R u+rwX "$ANDROID_SDK_CACHE"
}

stage_android_sdk

GRADLE_ARGS=("$@")
if [ "${#GRADLE_ARGS[@]}" -eq 0 ]; then
    GRADLE_ARGS=(assembleDebug --stacktrace -DskipFormatKtlint)
fi

echo "Building NewPipe debug APK with $IMAGE"
echo "Repository: $REPO_ROOT"
echo "Container user: $HOST_UID:$HOST_GID"
echo "Gradle args: ${GRADLE_ARGS[*]}"

podman run --rm \
    --name "$CONTAINER_NAME" \
    --userns keep-id \
    --user "$HOST_UID:$HOST_GID" \
    --memory 8g \
    --cpus 8 \
    -e HOME=/tmp/newpipe-home \
    -e GRADLE_USER_HOME=/gradle-cache \
    -e ANDROID_HOME=/android-sdk \
    -e ANDROID_SDK_ROOT=/android-sdk \
    -v "$REPO_ROOT:/workspace:Z" \
    -v "$GRADLE_CACHE:/gradle-cache:Z" \
    -v "$ANDROID_SDK_CACHE:/android-sdk:Z" \
    -w /workspace \
    "$IMAGE" \
    bash -lc '
        set -euo pipefail
        mkdir -p "$HOME" "$GRADLE_USER_HOME"

        SDKMANAGER=/android-sdk/cmdline-tools/latest/bin/sdkmanager
        if [ ! -x "$SDKMANAGER" ]; then
            echo "sdkmanager was not found in the staged Android SDK." >&2
            exit 1
        fi

        yes | "$SDKMANAGER" --sdk_root=/android-sdk --licenses >/dev/null || true

        if [ ! -d /android-sdk/platforms/android-36.1 ]; then
            "$SDKMANAGER" --sdk_root=/android-sdk --install "platforms;android-36.1"
        fi

        if ! ls /android-sdk/build-tools/36.* >/dev/null 2>&1; then
            "$SDKMANAGER" --sdk_root=/android-sdk --install "build-tools;36.0.0" \
                || "$SDKMANAGER" --sdk_root=/android-sdk --install "build-tools;36.1.0-rc1"
        fi

        ./gradlew "$@"
    ' bash "${GRADLE_ARGS[@]}"

if [ ! -f "$APK_PATH" ]; then
    echo "Build completed but APK was not found at $APK_PATH" >&2
    exit 1
fi

echo "Built APK: $APK_PATH"
