#!/bin/bash

# Run command: [bash scripts/pub_publish.sh]

# This script is intended for publishing freezed_go_style on pub.dev.
# Before publishing, the script performs code analysis, tests, package verification, and code formatting.

# Change to the root directory of the project
cd "$(dirname "$0")/.."

Enhance Freezed GoStyle Formatter with verbose logging and improved path handling

# Your comments for the changelog split by "/"
comments=(
  "Added verbose logging for debugging purposes in the formatter and CLI tool"
  "Improved path resolution for locating the `freezed_go_style` CLI tool, including checks for bundled, workspace, and global installations"
  "Updated the VS Code extension to provide feedback on the CLI tool's status and errors"
  "Enhanced the formatting logic to handle comments and annotations more effectively in Dart files"
)

# Increment the version number
echo -e "\033[32mIncrementing the version number...\033[0m"

# Increment version in pubspec.yaml
awk -F'.' -v OFS='.' '/version:/{++$3}1' pubspec.yaml > temp && mv temp pubspec.yaml

# Extract new version from pubspec.yaml
new_version=$(awk -F' ' '/version:/{print $2}' pubspec.yaml)

echo -e "\033[32mNew version: $new_version\033[0m"

# Update version in README.md (if it contains version references)
if grep -q "freezed_go_style.*[0-9]\+\.[0-9]\+\.[0-9]\+" README.md; then
    # Use perl for more reliable regex replacement on macOS
    perl -i -pe "s/freezed_go_style: \^[0-9]+\.[0-9]+\.[0-9]+/freezed_go_style: ^$new_version/g" README.md
    echo -e "\033[32mUpdated version in README.md\033[0m"
fi

# Update CHANGELOG.md
echo -e "\033[32mUpdating CHANGELOG.md...\033[0m"

# Create changelog entry
changelog_entry="## $new_version

"
for comment in "${comments[@]}"; do
    changelog_entry+="- $comment
"
done
changelog_entry+="
"

# Create temporary file with new changelog entry
echo "$changelog_entry" > temp_changelog.md
cat CHANGELOG.md >> temp_changelog.md
mv temp_changelog.md CHANGELOG.md

echo -e "\033[32mUpdated CHANGELOG.md\033[0m"

# Compile Dart CLI to native executable
echo -e "\033[32mCompiling Dart CLI to native executable...\033[0m"
dart compile exe bin/freezed_go_style.dart -o bin/freezed_go_style

if [ $? -ne 0 ]; then
    echo -e "\033[31m❌ Failed to compile executable\033[0m"
    exit 1
fi

echo -e "\033[32m✅ Compiled successfully\033[0m"

# Run code analysis
echo -e "\033[32mRunning code analysis...\033[0m"
dart analyze

# Run tests (if any)
echo -e "\033[32mRunning tests...\033[0m"
dart test

# Format code
echo -e "\033[32mFormatting code...\033[0m"
dart format lib/ bin/

# Dry run to check for issues
echo -e "\033[32mRunning dry-run...\033[0m"
dart pub publish --dry-run

# Ask for confirmation
echo -e "\033[33mDo you want to publish freezed_go_style $new_version to pub.dev? (y/N)\033[0m"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    # Commit changes first
    echo -e "\033[32mCommitting changes...\033[0m"
    git add .
    git commit -m "Release $new_version
    
$(for comment in "${comments[@]}"; do echo "- $comment"; done)"
    
    # Create git tag
    echo -e "\033[32mCreating git tag...\033[0m"
    git tag -a "v$new_version" -m "Release $new_version"
    
    # Push changes to remote
    echo -e "\033[32mPushing changes to remote...\033[0m"
    git push && git push --tags
    
    if [ $? -ne 0 ]; then
        echo -e "\033[31m❌ Failed to push changes to remote\033[0m"
        echo -e "\033[33mPlease push manually: git push && git push --tags\033[0m"
        exit 1
    fi
    
    # Now publish to pub.dev
    echo -e "\033[32mPublishing to pub.dev...\033[0m"
    dart pub publish
    
    if [ $? -eq 0 ]; then
        echo -e "\033[32m✅ Successfully published freezed_go_style $new_version!\033[0m"
        echo -e "\033[32m✅ Release $new_version completed successfully!\033[0m"
        echo -e "\033[32m📋 Next steps:\033[0m"
        echo -e "\033[32m   - Package will be available on pub.dev in 5-10 minutes\033[0m"
        echo -e "\033[32m   - Users can add it to pubspec.yaml: freezed_go_style: ^$new_version\033[0m"
        echo -e "\033[32m   - Don't forget to build and publish VS Code extension separately\033[0m"
    else
        echo -e "\033[31m❌ Failed to publish package\033[0m"
        echo -e "\033[33mChanges have been committed and pushed, but package publishing failed\033[0m"
        exit 1
    fi
else
    echo -e "\033[33mPublishing cancelled\033[0m"
    exit 0
fi
