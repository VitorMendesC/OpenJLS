#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF_DIR="$SCRIPT_DIR/../Verification/Reference Images"
ZIP_URL="https://www.itu.int/rec/dologin_pub.asp?lang=e&id=T-REC-T.87-199806-I!!ZPF-E&type=items"
WORK_DIR=$(mktemp -d)

trap 'rm -rf "$WORK_DIR"' EXIT

echo "Downloading T.87 reference package..."
curl -L -o "$WORK_DIR/t87.zip" "$ZIP_URL"

echo "Extracting outer archive..."
unzip -q "$WORK_DIR/t87.zip" -d "$WORK_DIR/t87"

echo "Extracting Software.zip..."
unzip -q "$WORK_DIR/t87/software/T87/Software.zip" -d "$WORK_DIR/software"

echo "Extracting jlsimgV100.zip..."
unzip -q "$WORK_DIR/software/software/T87/jlsimgV100.zip" -d "$WORK_DIR/jlsimgV100"

echo "Copying reference images to $REF_DIR/T87..."
mkdir -p "$REF_DIR/T87"
cp "$WORK_DIR"/jlsimgV100/* "$REF_DIR/T87/"

echo "Cleaning up non-image files from Reference Images..."
find "$REF_DIR" -maxdepth 1 -type f -delete

echo "Done. Reference images are in: $REF_DIR/T87/"
ls "$REF_DIR/T87/"
