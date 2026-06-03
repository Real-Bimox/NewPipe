#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
BIN_PATH="$BIN_DIR/newpipe-waydroid"
DESKTOP_PATH="$APP_DIR/org.schabi.newpipe.waydroid.desktop"
ICON_PATH="$REPO_ROOT/assets/new_pipe_icon_5.png"
LAUNCHER_PATH="$REPO_ROOT/packaging/waydroid/newpipe-waydroid.sh"

mkdir -p "$BIN_DIR" "$APP_DIR"

ln -sf "$LAUNCHER_PATH" "$BIN_PATH"

cat > "$DESKTOP_PATH" <<EOF
[Desktop Entry]
Type=Application
Name=NewPipe (Waydroid)
Comment=Launch the local NewPipe APK in Waydroid
Exec=$BIN_PATH
Icon=$ICON_PATH
Terminal=false
Categories=AudioVideo;Video;Network;
StartupNotify=false
EOF

chmod +x "$LAUNCHER_PATH"
chmod +x "$BIN_PATH"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Installed launcher:"
echo "  $BIN_PATH"
echo "  $DESKTOP_PATH"
