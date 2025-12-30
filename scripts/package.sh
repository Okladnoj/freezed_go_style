#!/bin/bash

# Run command: [bash freezed_go_style/scripts/package.sh]

cd freezed_go_style/vscode-extension

# Install dependencies if node_modules doesn't exist
if [ ! -d "node_modules" ]; then
  echo "Installing npm dependencies..."
  npm install
fi

npm run compile
vsce package

# cursor --uninstall-extension freezed-go-style.freezed-go-style