#!/usr/bin/env bash
set -euo pipefail

# Install-DashcamGUI.sh
# Usage: Install-DashcamGUI.sh --version <version>

usage() {
  cat <<EOF
Usage: $0 --version VERSION

Downloads the Dashcam GUI portable release for macOS, installs the .app to
/Applications (using sudo when required), creates helpful user_data files and
settings.json, and launches the application.

Options:
  --version, -v   Dashcam GUI version (example: 1.2.3)
  --help, -h      Show this help
EOF
}

if [ $# -eq 0 ]; then
  usage
  exit 1
fi

VERSION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version|-v)
      VERSION="$2"; shift 2;;
    --help|-h)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "--version is required" >&2
  usage
  exit 1
fi

echo "Installing Dashcam GUI version $VERSION for macOS"

INSTALL_DIR="$(mktemp -d -t dashcam-gui.XXXXXX)"
echo "Using temporary install directory: $INSTALL_DIR"

# Download the arm64 zip file
ASSET_URL_BASE="https://github.com/replayableio/replayable/releases/download/v${VERSION}"
FILENAME="Dashcam-${VERSION}-arm64-mac.zip"
DEST="$INSTALL_DIR/$FILENAME"

echo "Trying $ASSET_URL_BASE/$FILENAME"
if ! curl -fSL -o "$DEST" "$ASSET_URL_BASE/$FILENAME"; then
  echo "Failed to download $FILENAME from $ASSET_URL_BASE" >&2
  exit 2
fi

DOWNLOADED="$DEST"

if [ -z "$DOWNLOADED" ]; then
  echo "Failed to find a Dashcam portable artifact for version $VERSION" >&2
  exit 2
fi

# Zip extraction
echo "Unzipping..."
unzip -q "$DOWNLOADED" -d "$INSTALL_DIR/extracted"
APP_PATH="$(find "$INSTALL_DIR/extracted" -maxdepth 3 -name "*.app" -print -quit || true)"

if [ -z "$APP_PATH" ]; then
  echo "Could not locate Dashcam .app after extraction." >&2
  exit 5
fi

echo "Found app at: $APP_PATH"

# Install to /Applications
TARGET_APP="/Applications/$(basename "$APP_PATH")"
if [ -d "$TARGET_APP" ]; then
  echo "Removing existing application at $TARGET_APP"
  if [ -w "$TARGET_APP" ]; then
    rm -rf "$TARGET_APP"
  else
    sudo rm -rf "$TARGET_APP"
  fi
fi

echo "Copying app to /Applications"
if [ -w "/Applications" ]; then
  cp -R "$APP_PATH" "/Applications/"
else
  sudo cp -R "$APP_PATH" "/Applications/"
fi

# Create user_data directory and files similar to the Windows installer
USER_DATA_DIR="$INSTALL_DIR/user_data"
mkdir -p "$USER_DATA_DIR"

CONFIG_FILES=(
  ".replayable--mainwindow-ever-launched"
  ".replayable--has-accepted-tos"
  ".replayable--segment-done"
  ".replayable--ever-launched"
  ".replayable--do-not-update"
  ".replayable--do-not-open-browser"
)

for f in "${CONFIG_FILES[@]}"; do
  touch "$USER_DATA_DIR/$f"
done

cat > "$USER_DATA_DIR/settings.json" <<'JSON'
{
  "EDIT_ON_CLIP": false,
  "CAPTURE_ERROR": false,
  "DETECT_ERRORS_ONCE": true
}
JSON

echo "Created user_data at $USER_DATA_DIR"

# Launch the app
echo "Launching Dashcam.app from /Applications"
if open "/Applications/$(basename "$APP_PATH")"; then
  echo "Dashcam started"
else
  echo "Failed to launch Dashcam via open; attempting to run from installed bundle"
  if [ -d "$TARGET_APP" ]; then
    exec "${TARGET_APP}/Contents/MacOS/$(basename "${TARGET_APP%.*}")" &
  else
    echo "Cannot locate installed app to run." >&2
    exit 6
  fi
fi

echo "Installation complete. Temporary files are in $INSTALL_DIR (will be removed)."

# Note: we intentionally do not remove INSTALL_DIR right away so logs and user_data
# are available immediately after the script. Remove if desired.

exit 0
