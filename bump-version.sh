#!/bin/bash
# Usage: ./bump-version.sh <new-version>
# Example: ./bump-version.sh 1.4.0

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <new-version>"
  echo "Example: $0 1.4.0"
  echo ""
  echo "Current version: $(node -p "require('./package.json').version")"
  exit 1
fi

VERSION="$1"

# Validate semver format
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: Version must be in semver format (e.g. 1.4.0)"
  exit 1
fi

echo "Bumping version to $VERSION"

# Update root package.json
npm --no-git-tag-version version "$VERSION" 2>/dev/null
echo "  Updated package.json"

# Update client/package.json
cd client
npm --no-git-tag-version version "$VERSION" 2>/dev/null
cd ..
echo "  Updated client/package.json"

echo ""
echo "Done. Version is now $VERSION"
echo "Don't forget to commit: git add package.json client/package.json && git commit -m 'chore: bump version to $VERSION'"
