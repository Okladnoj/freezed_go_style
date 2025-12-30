#!/bin/bash

# Run command: [bash scripts/publish_openvsx.sh]
# This script publishes the extension to Open VSX Registry (for Cursor, Gravity, etc.)

cd "$(dirname "$0")/../vscode-extension"

echo -e "\033[32m📦 Publishing to Open VSX Registry\033[0m"
echo ""

# Check if ovsx is installed
if ! command -v ovsx &> /dev/null; then
    echo -e "\033[33m⚠️  ovsx not found. Installing...\033[0m"
    npm install -g ovsx
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo -e "\033[32mInstalling npm dependencies...\033[0m"
    npm install
fi

# Compile TypeScript
echo -e "\033[32mCompiling TypeScript...\033[0m"
npm run compile

if [ $? -ne 0 ]; then
    echo -e "\033[31m❌ Compilation failed\033[0m"
    exit 1
fi

# Package extension
echo -e "\033[32mPackaging extension...\033[0m"
if ! command -v vsce &> /dev/null; then
    echo -e "\033[33m⚠️  vsce not found. Installing...\033[0m"
    npm install -g @vscode/vsce
fi

vsce package

if [ $? -ne 0 ]; then
    echo -e "\033[31m❌ Packaging failed\033[0m"
    exit 1
fi

# Find the .vsix file
VSIX_FILE=$(ls -t *.vsix 2>/dev/null | head -1)

if [ -z "$VSIX_FILE" ]; then
    echo -e "\033[31m❌ .vsix file not found\033[0m"
    exit 1
fi

echo -e "\033[32m✅ Extension packaged: $VSIX_FILE\033[0m"
echo ""

# Check for token
if [ -z "$OPEN_VSX_TOKEN" ]; then
    echo -e "\033[33m⚠️  OPEN_VSX_TOKEN not set\033[0m"
    echo ""
    echo -e "\033[32m📋 Before publishing, you need to:\033[0m"
    echo ""
    echo -e "\033[33m1. Sign the Publisher Agreement:\033[0m"
    echo "   - Go to: https://open-vsx.org"
    echo "   - Click on your profile icon (top right)"
    echo "   - Go to 'PROFILE' section"
    echo "   - Sign the 'Eclipse Foundation Open VSX Publisher Agreement'"
    echo ""
    echo -e "\033[33m2. Create a Namespace (if not exists):\033[0m"
    echo "   - Go to: https://open-vsx.org"
    echo "   - Click on your profile icon → 'NAMESPACES'"
    echo "   - Click 'Create Namespace'"
    echo "   - Enter namespace: OKJI"
    echo "   - If namespace already exists or is taken, you may need to:"
    echo "     * Use a different namespace (update package.json publisher field)"
    echo "     * Or request namespace ownership via GitHub issue"
    echo ""
    echo -e "\033[33m3. Create a Personal Access Token:\033[0m"
    echo "   - Go to 'ACCESS TOKENS' section"
    echo "   - Click 'Generate New Token'"
    echo "   - Copy the token"
    echo ""
    echo -e "\033[33m4. Then either:\033[0m"
    echo "   - Set token: export OPEN_VSX_TOKEN=your_token_here"
    echo "   - Or login with: ovsx login OKJI"
    echo ""
    echo -e "\033[33mDo you want to try login now? (y/N)\033[0m"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "\033[32mLogging in to Open VSX...\033[0m"
        ovsx login OKJI
        if [ $? -ne 0 ]; then
            echo ""
            echo -e "\033[31m❌ Login failed. Make sure you:\033[0m"
            echo "   1. Signed the Publisher Agreement on https://open-vsx.org"
            echo "   2. Created namespace 'OKJI' in NAMESPACES section"
            echo "   3. Created a Personal Access Token"
            echo ""
            echo -e "\033[33mYou can also set the token manually:\033[0m"
            echo "   export OPEN_VSX_TOKEN=your_token_here"
            echo "   bash scripts/publish_openvsx.sh"
            exit 1
        fi
    else
        echo -e "\033[33mPublishing cancelled.\033[0m"
        echo -e "\033[32mTo publish later, either:\033[0m"
        echo "   1. Set token: export OPEN_VSX_TOKEN=your_token_here"
        echo "   2. Or run: ovsx login OKJI"
        exit 0
    fi
fi

# Publish to Open VSX
echo -e "\033[32mPublishing to Open VSX Registry...\033[0m"

# Try to publish with token if available, otherwise use login session
if [ -n "$OPEN_VSX_TOKEN" ]; then
    ovsx publish "$VSIX_FILE" --pat "$OPEN_VSX_TOKEN"
else
    # Use login session (token stored by ovsx login)
    ovsx publish "$VSIX_FILE"
fi

if [ $? -eq 0 ]; then
    echo ""
    echo -e "\033[32m✅ Successfully published to Open VSX Registry!\033[0m"
    echo -e "\033[32m📋 Extension will be available in a few minutes at:\033[0m"
    echo -e "\033[36m   https://open-vsx.org/extension/OKJI/freezed-go-style\033[0m"
    echo ""
    echo -e "\033[32m✨ Now available in:\033[0m"
    echo "   - Cursor"
    echo "   - Gravity"
    echo "   - VSCodium"
    echo "   - Eclipse Theia"
    echo "   - And other Open VSX compatible editors"
else
    echo ""
    echo -e "\033[31m❌ Failed to publish to Open VSX Registry\033[0m"
    echo ""
    echo -e "\033[33mCommon issues:\033[0m"
    echo "   1. Namespace 'OKJI' not found:"
    echo "      → Go to https://open-vsx.org → Profile → NAMESPACES"
    echo "      → Click 'Create Namespace' and create 'OKJI'"
    echo ""
    echo "   2. Invalid token:"
    echo "      → Make sure you created a new token in ACCESS TOKENS"
    echo "      → Token should start with 'ovsxat_'"
    echo ""
    echo "   3. Publisher Agreement not signed:"
    echo "      → Go to Profile → Sign the agreement"
    echo ""
    echo -e "\033[32mAfter fixing the issue, try again:\033[0m"
    echo "   export OPEN_VSX_TOKEN=your_token_here"
    echo "   bash scripts/publish_openvsx.sh"
    exit 1
fi

