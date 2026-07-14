#!/bin/bash
# One-time setup: create the Python venv and install dependencies.
set -euo pipefail
cd "$(dirname "$0")"

python3 -m venv venv
venv/bin/pip install --upgrade pip
venv/bin/pip install mlx-whisper numpy

if [ ! -f glossary.json ]; then
    cp glossary.example.json glossary.json
    echo "Created glossary.json from the example — add your own terms to it."
fi

echo "Done. The app starts the server automatically; manual start:"
echo "  venv/bin/python transcribe_server.py"
