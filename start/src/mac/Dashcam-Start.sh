#!/usr/bin/env bash
set -euo pipefail

# Dashcam-Start.sh
# Usage: Dashcam-Start.sh --api-key <key> [--log-file-paths "line1\nline2"] --timeout <seconds>

usage() {
  cat <<EOF
Usage: $0 --api-key API_KEY --timeout SECONDS [--log-file-paths "PATH1\nPATH2"]

Starts Dashcam recording on macOS. Mirrors the behavior of the Windows
`Dashcam-Start.ps1` script: waits for the Dashcam GUI process to appear,
authenticates the CLI with the provided API key, adds file trackers, and
starts recording.

Options:
  --api-key, -k        Dashcam API key (required)
  --log-file-paths, -l Newline-separated list of file paths to tail (optional)
  --timeout, -t        Timeout in seconds to wait for the GUI (required)
  --help, -h           Show this help
EOF
}

if [ $# -eq 0 ]; then
  usage
  exit 1
fi

API_KEY=""
LOG_FILE_PATHS=""
TIMEOUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --api-key|-k)
      API_KEY="$2"; shift 2;;
    --log-file-paths|-l)
      LOG_FILE_PATHS="$2"; shift 2;;
    --timeout|-t)
      TIMEOUT="$2"; shift 2;;
    --help|-h)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

if [ -z "$API_KEY" ] || [ -z "$TIMEOUT" ]; then
  echo "--api-key and --timeout are required" >&2
  usage
  exit 1
fi

echo "::group::Checking Dashcam availability."
APP_NAME="Dashcam"
ELAPSED=0

# Wait until the Dashcam GUI process is visible or timeout elapses
while ! pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  echo "Waiting for $APP_NAME to start... ($ELAPSED/$TIMEOUT)"
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
  echo "Timeout reached. $APP_NAME was not available from shell."
  echo "::endgroup::"
  exit 1
else
  echo "$APP_NAME has started."
  echo "::endgroup::"
fi

echo "Dashcam GUI started and ready to begin recording."
echo "::group::Starting Dashcam recording."

# If an install step exported DASHCAM_NODE_DIR, include it and an npm-installs dir
if [ -n "${DASHCAM_NODE_DIR:-}" ]; then
  export PATH="$DASHCAM_NODE_DIR:$DASHCAM_NODE_DIR/npm-installs:$PATH"
  echo "Added DASHCAM_NODE_DIR to PATH: $DASHCAM_NODE_DIR"
fi

# Ensure dashcam CLI is available
if ! command -v dashcam >/dev/null 2>&1; then
  echo "dashcam CLI not found in PATH. Make sure the Dashcam CLI is installed and its bin directory is on PATH." >&2
  exit 1
fi

echo "Authenticating dashcam CLI..."
AUTH_OUTPUT="$(dashcam auth "$API_KEY" 2>&1 || true)"
echo "outputting..."
echo "outputting AUTH OUTPUT for debugging: $AUTH_OUTPUT"
echo "$AUTH_OUTPUT"

if [[ "$AUTH_OUTPUT" == *"Connected as"* ]]; then
  echo "Dashcam authenticated."
else
  echo "Failed to authenticate with Dashcam." >&2
  exit 1
fi

# If log file paths were provided, split on newlines and create track entries
if [ -n "$LOG_FILE_PATHS" ]; then
  i=0
  # Use printf to preserve newlines and feed into while-read loop
  printf '%s\n' "$LOG_FILE_PATHS" | while IFS= read -r line; do
    # Skip empty lines
    if [ -z "$(echo "$line" | tr -d '[:space:]')" ]; then
      continue
    fi
    echo "Dashcam will tail: $line"
    dashcam track --type application --name "log-file-$i" --pattern "$line"
    i=$((i + 1))
  done
fi

echo "Starting dashcam recording..."
dashcam start

echo "Dashcam recording has started."
echo "::endgroup::"

exit 0
