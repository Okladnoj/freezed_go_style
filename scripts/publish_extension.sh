#!/bin/bash

# Run command: [bash scripts/publish_extension.sh]

# This script publishes the VS Code extension to the marketplace

cd "$(dirname "$0")/../vscode-extension"

echo -e "\033[32m📦 Publishing VS Code Extension\033[0m"
echo ""

# Check if vsce is installed
if ! command -v vsce &> /dev/null; then
    echo -e "\033[33m⚠️  vsce not found. Installing...\033[0m"
    npm install -g @vscode/vsce
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

# Check if logged in
echo -e "\033[32mChecking publisher status...\033[0m"
vsce ls-publishers 2>&1 | grep -q "OKJI"

if [ $? -ne 0 ]; then
    echo -e "\033[33m⚠️  Not logged in as publisher 'OKJI'\033[0m"
    echo ""
    echo -e "\033[32mTo publish, you need to:\033[0m"
    echo "1. Create a publisher at: https://marketplace.visualstudio.com/manage"
    echo "2. Get a Personal Access Token (PAT) from: https://dev.azure.com"
    echo "3. Login with: vsce login OKJI"
    echo ""
    echo -e "\033[33mDo you want to login now? (y/N)\033[0m"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        vsce login OKJI
    else
        echo -e "\033[33mPublishing cancelled. Please login first.\033[0m"
        exit 0
    fi
fi

# Package extension
echo -e "\033[32mPackaging extension...\033[0m"
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

# Ask which marketplace to publish to
echo -e "\033[33mWhere do you want to publish?\033[0m"
echo "1) VS Code Marketplace (VS Code only)"
echo "2) Open VSX Registry (Cursor, Gravity, VSCodium, etc.)"
echo "3) Both"
echo ""
read -p "Enter choice (1-3): " choice

case $choice in
    1)
        echo -e "\033[32mPublishing to VS Code Marketplace...\033[0m"
        vsce publish
        
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "\033[32m✅ Successfully published to VS Code Marketplace!\033[0m"
            echo -e "\033[36m   https://marketplace.visualstudio.com/items?itemName=OKJI.freezed-go-style\033[0m"
        else
            echo -e "\033[31m❌ Failed to publish to VS Code Marketplace\033[0m"
            exit 1
        fi
        ;;
    2)
        # Check if ovsx is installed
        if ! command -v ovsx &> /dev/null; then
            echo -e "\033[33m⚠️  ovsx not found. Installing...\033[0m"
            npm install -g ovsx
        fi
        
        echo -e "\033[32mPublishing to Open VSX Registry...\033[0m"
        echo -e "\033[33mNote: Make sure you:\033[0m"
        echo -e "\033[33m  1. Created namespace 'OKJI' at https://open-vsx.org → Profile → NAMESPACES\033[0m"
        echo -e "\033[33m  2. Have a valid Personal Access Token\033[0m"
        echo ""
        
        if [ -z "$OPEN_VSX_TOKEN" ]; then
            echo -e "\033[33mEnter your Personal Access Token:\033[0m"
            read -s OPEN_VSX_TOKEN
            echo ""
        fi
        
        ovsx publish "$VSIX_FILE" --pat "$OPEN_VSX_TOKEN"
        
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "\033[32m✅ Successfully published to Open VSX Registry!\033[0m"
            echo -e "\033[36m   https://open-vsx.org/extension/OKJI/freezed-go-style\033[0m"
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
            echo "      → Make sure token is correct and starts with 'ovsxat_'"
            echo ""
            echo -e "\033[33mOr login with: ovsx login OKJI\033[0m"
            exit 1
        fi
        ;;
    3)
        # Publish to VS Code Marketplace
        echo -e "\033[32mPublishing to VS Code Marketplace...\033[0m"
        vsce publish
        
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "\033[32m✅ Successfully published to VS Code Marketplace!\033[0m"
            echo -e "\033[36m   https://marketplace.visualstudio.com/items?itemName=OKJI.freezed-go-style\033[0m"
        else
            echo -e "\033[31m❌ Failed to publish to VS Code Marketplace\033[0m"
            exit 1
        fi
        
        echo ""
        
        # Publish to Open VSX Registry
        if ! command -v ovsx &> /dev/null; then
            echo -e "\033[33m⚠️  ovsx not found. Installing...\033[0m"
            npm install -g ovsx
        fi
        
        echo -e "\033[32mPublishing to Open VSX Registry...\033[0m"
        echo -e "\033[33mNote: You need to create an account at https://open-vsx.org and get a Personal Access Token\033[0m"
        
        ovsx publish "$VSIX_FILE" --pat "$OPEN_VSX_TOKEN"
        
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "\033[32m✅ Successfully published to Open VSX Registry!\033[0m"
            echo -e "\033[36m   https://open-vsx.org/extension/OKJI/freezed-go-style\033[0m"
        else
            echo -e "\033[33m⚠️  Failed to publish to Open VSX Registry\033[0m"
            echo -e "\033[33mMake sure you have set OPEN_VSX_TOKEN environment variable:\033[0m"
            echo -e "\033[36m   export OPEN_VSX_TOKEN=your_token_here\033[0m"
            echo -e "\033[33mOr login with: ovsx login\033[0m"
        fi
        ;;
    *)
        echo -e "\033[33mPublishing cancelled\033[0m"
        echo -e "\033[32mExtension packaged as .vsix file. You can publish it later.\033[0m"
        ;;
esac

