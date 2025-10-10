#!/usr/bin/env bash
set -euo pipefail

# Install-DashcamCLI.sh
# Usage: Install-DashcamCLI.sh --version <version>

usage() {
  cat <<EOF
Usage: $0 --version VERSION

Installs the Dashcam CLI globally via npm and verifies the installation.

Options:
  --version, -v   Dashcam CLI version (example: 1.2.3 or "latest")
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

echo "Installing Dashcam CLI $VERSION..."

# Verify npm is available
if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found in PATH. Make sure Node.js/npm is installed and on PATH." >&2
  exit 2
fi

echo "Using npm: $(npm --version)"

# Try installing without sudo first. If it fails due to permission, retry with sudo.
if npm install --location=global "dashcam@$VERSION"; then
  echo "dashcam installed successfully (no sudo)"
else
  echo "Initial npm install failed; retrying with sudo..."
  if sudo npm install --location=global "dashcam@$VERSION"; then
    echo "dashcam installed successfully (with sudo)"
  else
    echo "Failed to install dashcam globally via npm." >&2
    exit 3
  fi
fi

echo "Verifying Dashcam CLI Install..."

if ! command -v dashcam >/dev/null 2>&1; then
  echo "dashcam binary not found in PATH." >&2
  echo "If you set a custom npm prefix, ensure its bin/ directory is on PATH. Example:"
  echo "  export PATH=\"\${NODE_PREFIX:-/usr/local}/bin:\$PATH\""
  echo "You can also run: npm bin -g to find the global bin directory."
  exit 4
fi

dashcam --help || { echo "dashcam --help failed" >&2; exit 5; }
dashcam --version || { echo "dashcam --version failed" >&2; exit 6; }

echo "Dashcam CLI installed and verified."

exit 0
