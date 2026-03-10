#!/bin/bash
set -e

APP_NAME="Localhost Runner"
BUNDLE_DIR=".build/release/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

# Build release binary
swift build -c release

# Create .app bundle structure
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"

# Copy binary and Info.plist
cp .build/release/LocalhostRunner "${MACOS_DIR}/LocalhostRunner"
cp Info.plist "${CONTENTS_DIR}/Info.plist"

echo "Built: ${BUNDLE_DIR}"
