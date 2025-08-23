#!/bin/sh
set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

VERSION="$1"
RELEASE_DIR="./releases"
OUTPUT="$RELEASE_DIR/koderum_${VERSION}.zip"

mkdir -p "$RELEASE_DIR"

odin build src -o:speed -out:koderum

zip -r "$OUTPUT" koderum ./languages ./config
