#!/bin/bash
# WhisperKey one-line installer:
#   curl -fsSL https://raw.githubusercontent.com/dojdikkkkkk/WhisperKey/main/install.sh | bash
# Idempotent: re-running updates an existing install.
set -euo pipefail

REPO="https://github.com/dojdikkkkkk/WhisperKey"
DIR="$HOME/WhisperKey"

echo "==> Checking prerequisites"
if [ "$(uname -m)" != "arm64" ]; then
    echo "ERROR: WhisperKey requires an Apple Silicon Mac (MLX runs on the M-series GPU)." >&2
    exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are missing. Launching the installer..."
    xcode-select --install
    echo "Re-run this script after the tools finish installing." >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 not found. Install it (e.g. 'brew install python') and re-run." >&2
    exit 1
fi

echo "==> Fetching WhisperKey into $DIR"
if [ -d "$DIR/.git" ]; then
    git -C "$DIR" pull --ff-only
else
    git clone "$REPO" "$DIR"
fi

echo "==> Setting up the transcription server (Python venv)"
"$DIR/server/setup.sh"

echo "==> Building the app"
"$DIR/build.sh"

echo "==> Launching"
open /Applications/WhisperKey.app

cat <<'EOF'

Almost there! Grant two permissions in System Settings -> Privacy & Security:
  1. Microphone     -> allow WhisperKey
  2. Accessibility  -> add /Applications/WhisperKey.app and enable it
Then RELAUNCH the app (quit from the menu bar icon, open again).

Dictate: hold right-Cmd and speak (push-to-talk), or tap right-Cmd to toggle.
The setup wizard lets you choose Local MLX or your own Cloud API, plus glossary learning.
EOF
