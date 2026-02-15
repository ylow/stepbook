#!/usr/bin/env bash
set -euo pipefail

echo "==> Building client..."
npm run build

echo "==> Building Mac DMG..."
npx electron-builder --mac

echo "==> Building Windows installer (x64)..."
npx electron-builder --win --x64

echo "==> Restoring native modules for local dev..."
rm -f node_modules/better-sqlite3/build/Release/better_sqlite3.node
npx @electron/rebuild -m . -o better-sqlite3 -f

echo "==> Done. Artifacts in dist-electron/:"
ls -lh dist-electron/*.dmg dist-electron/*.exe 2>/dev/null
