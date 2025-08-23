#!/bin/sh
set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

VERSION="$1"
RELEASE_DIR="./releases"
OUTPUT="$RELEASE_DIR/koderum_${VERSION}.zip"

# Ensure releases dir exists
mkdir -p "$RELEASE_DIR"

# Build with Odin
odin build src -o:speed

# Collect files
zip -r "$OUTPUT" src.bin ./languages ./config


