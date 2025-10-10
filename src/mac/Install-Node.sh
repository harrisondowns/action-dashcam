
#!/usr/bin/env bash
set -euo pipefail

# Install-Node.sh
# Usage: Install-Node.sh --version <version> --directory <install-directory> --prefix <npm-prefix>
# Example: ./Install-Node.sh --version 16.20.0 --directory /usr/local/node-16 --prefix /usr/local

usage() {
	cat <<EOF
Usage: $0 --version VERSION --directory DIRECTORY --prefix PREFIX

Downloads the Node.js tarball for the current macOS architecture, verifies its
SHA256 against the official SHASUMS256.txt, extracts it into DIRECTORY and
configures npm to use PREFIX as its global prefix.

Options:
	--version, -v   Node.js version (example: 16.20.0)
	--directory, -d Directory to install node into (will contain bin/, lib/, ...)
	--prefix, -p    npm prefix to configure (npm global packages location)
	--help, -h      Show this help
EOF
}

if [ $# -eq 0 ]; then
	usage
	exit 1
fi

VERSION=""
DIRECTORY=""
PREFIX=""

while [ $# -gt 0 ]; do
	case "$1" in
		--version|-v)
			VERSION="$2"; shift 2;;
		--directory|-d)
			DIRECTORY="$2"; shift 2;;
		--prefix|-p)
			PREFIX="$2"; shift 2;;
		--help|-h)
			usage; exit 0;;
		*)
			echo "Unknown option: $1" >&2; usage; exit 1;;
	esac
done

if [ -z "$VERSION" ] || [ -z "$DIRECTORY" ] || [ -z "$PREFIX" ]; then
	echo "All of --version, --directory and --prefix are required." >&2
	usage
	exit 1
fi

# Determine architecture for Node distributions
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
	x86_64) ARCH="darwin-x64";;
	arm64)  ARCH="darwin-arm64";;
	*)
		echo "Unknown architecture '$ARCH_RAW' — defaulting to darwin-x64" >&2
		ARCH="darwin-x64";;
esac

TARBALL="node-v${VERSION}-${ARCH}.tar.gz"
TARBALL_URL="https://nodejs.org/dist/v${VERSION}/${TARBALL}"
SHASUM_URL="https://nodejs.org/dist/v${VERSION}/SHASUMS256.txt"

TMPDIR="$(mktemp -d -t install-node.XXXXXX)"
TARBALL_PATH="$TMPDIR/$TARBALL"
SHASUM_PATH="$TMPDIR/SHASUMS256.txt"

echo "Downloading Node.js $VERSION for $ARCH..."
curl -fSL -o "$TARBALL_PATH" "$TARBALL_URL"
curl -fSL -o "$SHASUM_PATH" "$SHASUM_URL"

echo "Verifying SHA256..."
# Extract expected sha from SHASUMS256.txt (match exact filename at line end)
EXPECTED_SHA256="$(awk -v file="$TARBALL" '$2 == file {print $1}' "$SHASUM_PATH" || true)"
if [ -z "$EXPECTED_SHA256" ]; then
	echo "Failed to find expected SHA256 for $TARBALL in SHASUMS256.txt" >&2
	rm -rf "$TMPDIR"
	exit 1
fi

ACTUAL_SHA256="$(shasum -a 256 "$TARBALL_PATH" | awk '{print $1}')"

if [ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]; then
	echo "SHA256 mismatch for $TARBALL" >&2
	echo "Expected: $EXPECTED_SHA256" >&2
	echo "Actual:   $ACTUAL_SHA256" >&2
	rm -rf "$TMPDIR"
	exit 1
fi

echo "SHA256 verified. Installing to $DIRECTORY..."

# Ensure directory exists (use sudo if necessary)
if [ -d "$DIRECTORY" ]; then
	if [ ! -w "$DIRECTORY" ]; then
		echo "Directory exists but is not writable, will use sudo when extracting." >&2
		NEED_SUDO=1
	else
		NEED_SUDO=0
	fi
else
	# Try to create it, fall back to sudo
	if mkdir -p "$DIRECTORY" 2>/dev/null; then
		NEED_SUDO=0
	else
		echo "Creating $DIRECTORY requires elevated privileges; using sudo." >&2
		sudo mkdir -p "$DIRECTORY"
		NEED_SUDO=1
	fi
fi

# Extract tarball into DIRECTORY, stripping the top-level folder from the tarball
if [ "$NEED_SUDO" -eq 1 ]; then
	sudo tar --numeric-owner --strip-components=1 -xzf "$TARBALL_PATH" -C "$DIRECTORY"
else
	tar --strip-components=1 -xzf "$TARBALL_PATH" -C "$DIRECTORY"
fi

# Ensure bin is in PATH for the remainder of this script
export PATH="$DIRECTORY/bin:$PATH"

NPM_BIN="$DIRECTORY/bin/npm"
if [ ! -x "$NPM_BIN" ]; then
	echo "npm executable not found at $NPM_BIN" >&2
	rm -rf "$TMPDIR"
	exit 1
fi

echo "Configuring npm prefix to $PREFIX..."
if "$NPM_BIN" config set prefix "$PREFIX" 2>/dev/null; then
	echo "npm prefix set successfully (without sudo)"
else
	echo "npm prefix set requires elevated privileges; trying with sudo..."
	sudo "$NPM_BIN" config set prefix "$PREFIX"
fi

echo "NPM local configuration:"
"$NPM_BIN" config list || true
echo "NPM global configuration:"
if sudo -n true 2>/dev/null; then
	sudo "$NPM_BIN" config list -g || true
else
	# If sudo would prompt, run the command normally so user can authenticate
	"$NPM_BIN" config list -g || true
fi

echo "${DIRECTORY}/bin" >> $GITHUB_PATH
echo "${PREFIX}/bin" >> $GITHUB_PATH

echo "Installation complete."
echo "Add $DIRECTORY/bin to your PATH to use this node install (for example: export PATH=$DIRECTORY/bin:\$PATH)"

# Cleanup
rm -rf "$TMPDIR"

exit 0

