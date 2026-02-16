#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/build/ClaudeTokenBar.app"
BIN="$APP/Contents/MacOS/ClaudeTokenBar"

echo "Building ClaudeTokenBar..."
mkdir -p "$APP/Contents/MacOS"

swiftc \
    -swift-version 5 \
    -parse-as-library \
    -framework SwiftUI \
    -framework Security \
    -target arm64-apple-macosx14.0 \
    -O \
    -o "$BIN" \
    "$DIR/ClaudeTokenBar.swift"

echo "Build complete: $APP"
echo ""
echo "To install: cp -r '$APP' /Applications/"
echo "To run:     open '$APP'"
