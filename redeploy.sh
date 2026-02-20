#!/usr/bin/env bash
set -e

# redeploy.sh — Pull latest code, rebuild, and restart the service.
# Assumes deploy.sh has already been run (Node, Tailscale, systemd all set up).

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

echo "==> Pulling latest code..."
git pull --ff-only

echo "==> Installing server dependencies..."
npm install --omit=dev

echo "==> Installing client dependencies..."
npm install --prefix client

echo "==> Building client..."
npm run build

echo "==> Restarting stepbook service..."
sudo systemctl restart stepbook

echo "==> Done. Service status:"
systemctl is-active stepbook
