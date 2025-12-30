#!/bin/bash

# Define paths
ROOT_DIR=".."
EXT_DIR="."
BUNDLE_DIR="$EXT_DIR/cli"

echo "Bundling Dart CLI into extension..."

# Clean previous bundle
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# Copy necessary files
# We need bin, lib, and pubspec.yaml/lock
cp -r "$ROOT_DIR/bin" "$BUNDLE_DIR/"
cp -r "$ROOT_DIR/lib" "$BUNDLE_DIR/"
cp "$ROOT_DIR/pubspec.yaml" "$BUNDLE_DIR/"
cp "$ROOT_DIR/pubspec.lock" "$BUNDLE_DIR/"
cp "$ROOT_DIR/analysis_options.yaml" "$BUNDLE_DIR/"

echo "Dart CLI bundles into $BUNDLE_DIR"
echo "Now run: vsce package"
