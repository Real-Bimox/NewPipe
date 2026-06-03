#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

APK_PATH=${NEWPIPE_APK_PATH:-"$REPO_ROOT/app/build/outputs/apk/debug/app-debug.apk"}
PACKAGE_NAME=${NEWPIPE_PACKAGE_NAME:-org.schabi.newpipe.debug}
LOG_DIR=${NEWPIPE_WAYDROID_LOG_DIR:-"$HOME/.cache/newpipe-waydroid"}
SESSION_LOG="$LOG_DIR/waydroid-session.log"
INSTALL_APK=1
INSTALL_ONLY=0
SHOW_FULL_UI=0

if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    export WAYLAND_DISPLAY="wayland-0"
fi

usage() {
    cat <<EOF
Usage: newpipe-waydroid [options]

Options:
  --apk PATH       APK to install before launch.
  --no-install    Launch the existing Waydroid app without installing an APK.
  --install-only  Install or update the APK, then exit.
  --show-full-ui  Open the Waydroid full UI before launching NewPipe.
  -h, --help      Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --apk)
            if [ "$#" -lt 2 ]; then
                echo "--apk requires a path." >&2
                exit 2
            fi
            APK_PATH=$2
            shift 2
            ;;
        --no-install)
            INSTALL_APK=0
            shift
            ;;
        --install-only)
            INSTALL_ONLY=1
            shift
            ;;
        --show-full-ui)
            SHOW_FULL_UI=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! command -v waydroid >/dev/null 2>&1; then
    echo "waydroid is required but was not found on PATH." >&2
    exit 1
fi

mkdir -p "$LOG_DIR"

session_running() {
    waydroid status 2>&1 | grep -Eq "Session:[[:space:]]+RUNNING"
}

start_session() {
    if session_running; then
        return 0
    fi

    echo "Starting Waydroid session..."
    nohup waydroid session start >"$SESSION_LOG" 2>&1 &

    for _ in $(seq 1 60); do
        if session_running; then
            return 0
        fi
        sleep 1
    done

    echo "Waydroid session did not reach RUNNING state." >&2
    echo "Current status:" >&2
    waydroid status >&2 || true
    echo "Session log: $SESSION_LOG" >&2
    if [ -f "$SESSION_LOG" ]; then
        tail -40 "$SESSION_LOG" >&2 || true
    fi
    exit 1
}

wait_app_manager() {
    local output
    local status

    for _ in $(seq 1 30); do
        if output=$(timeout 12s waydroid app list 2>&1); then
            status=0
        else
            status=$?
            if [ "$status" -eq 124 ]; then
                output="waydroid app list timed out"
            fi
        fi
        if ! printf '%s\n' "$output" \
            | grep -Eq "WayDroid session is stopped|Failed to get service|timed out"; then
            return 0
        fi
        sleep 2
    done

    echo "Waydroid app manager did not become ready." >&2
    printf '%s\n' "$output" >&2
    exit 1
}

run_with_timeout() {
    local seconds=$1
    local output
    local status
    shift

    if output=$(timeout "$seconds" "$@" 2>&1); then
        printf '%s\n' "$output"
        return 0
    fi

    status=$?
    printf '%s\n' "$output"
    if [ "$status" -eq 124 ]; then
        echo "$* timed out after $seconds" >&2
    fi
    return "$status"
}

STATUS=$(waydroid status 2>&1 || true)
if printf '%s\n' "$STATUS" | grep -qi "not initialized"; then
    cat >&2 <<EOF
Waydroid is installed but not initialized.

Initialize Waydroid on the host first, then run this launcher again.
EOF
    exit 1
fi

start_session
wait_app_manager

if [ "$SHOW_FULL_UI" -eq 1 ]; then
    waydroid show-full-ui >/dev/null 2>&1 &
    sleep 2
fi

if [ "$INSTALL_APK" -eq 1 ]; then
    if [ ! -f "$APK_PATH" ]; then
        cat >&2 <<EOF
APK not found:
  $APK_PATH

Build it first:
  packaging/waydroid/build-debug-apk-in-podman.sh
EOF
        exit 1
    fi

    echo "Installing NewPipe APK into Waydroid..."
    INSTALL_STATUS=0
    INSTALL_OUTPUT=$(run_with_timeout 45s waydroid app install "$APK_PATH") || INSTALL_STATUS=$?
    printf '%s\n' "$INSTALL_OUTPUT"
    if [ "$INSTALL_STATUS" -ne 0 ] || printf '%s\n' "$INSTALL_OUTPUT" \
        | grep -Eq "WayDroid session is stopped|Failed to get service|Failed to access|timed out"; then
        echo "NewPipe APK install did not complete cleanly." >&2
        exit 1
    fi
fi

if [ "$INSTALL_ONLY" -eq 1 ]; then
    exit 0
fi

echo "Launching NewPipe in Waydroid..."
LAUNCH_STATUS=0
LAUNCH_OUTPUT=$(run_with_timeout 30s waydroid app launch "$PACKAGE_NAME") || LAUNCH_STATUS=$?
printf '%s\n' "$LAUNCH_OUTPUT"
if [ "$LAUNCH_STATUS" -ne 0 ] || printf '%s\n' "$LAUNCH_OUTPUT" \
    | grep -Eq "WayDroid session is stopped|Failed to get service|RuntimeError|Failed to access|timed out"; then
    echo "NewPipe launch did not complete cleanly." >&2
    exit 1
fi
