#!/usr/bin/env bash
set -e

# deploy.sh — One-shot deploy for Stepbook on a fresh Ubuntu/Debian VPS
# Installs Node.js 22, Tailscale, builds the app, creates a systemd service,
# and configures tailscale serve for HTTPS.
# Safe to re-run (idempotent).

# ── 0. Usage ─────────────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
  echo "Usage: $0 <data-dir>"
  echo "  <data-dir>  Directory for Stepbook data (e.g. /var/lib/stepbook)"
  exit 1
fi

DATA_DIR="$1"

# ── 1. Require root ──────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root (or with sudo)."
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "==> Repo directory: $REPO_DIR"

# ── 2. Install Node.js 22 LTS ───────────────────────────────────────────────
if command -v node &>/dev/null; then
  echo "==> Node.js already installed: $(node --version)"
else
  echo "==> Installing Node.js 22 LTS via NodeSource..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update -qq
  apt-get install -y -qq nodejs
  echo "==> Installed Node.js $(node --version)"
fi

# ── 3. Install Tailscale ────────────────────────────────────────────────────
if command -v tailscale &>/dev/null; then
  echo "==> Tailscale already installed: $(tailscale version | head -1)"
else
  echo "==> Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  echo "==> Tailscale installed."
fi

# ── 4. Ensure Tailscale is connected ────────────────────────────────────────
if tailscale status &>/dev/null; then
  echo "==> Tailscale is connected."
else
  echo "==> Tailscale is not connected. Running 'tailscale up'..."
  echo "    Follow the auth URL printed below to authenticate."
  tailscale up
  echo "==> Tailscale connected."
fi

# ── 5. Install npm dependencies ─────────────────────────────────────────────
echo "==> Installing server dependencies (omitting devDeps)..."
cd "$REPO_DIR"
npm install --omit=dev

echo "==> Installing client dependencies (including devDeps for build)..."
cd "$REPO_DIR/client"
npm install

# ── 6. Build client ─────────────────────────────────────────────────────────
echo "==> Building client..."
cd "$REPO_DIR"
npm run build

# ── 7. Create data directory ────────────────────────────────────────────────
mkdir -p "$DATA_DIR"
echo "==> Data directory: $DATA_DIR"

# ── 8. Write systemd unit ───────────────────────────────────────────────────
UNIT_FILE="/etc/systemd/system/stepbook.service"
echo "==> Writing systemd unit to $UNIT_FILE"
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Stepbook Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$REPO_DIR
ExecStart=$(command -v node) $REPO_DIR/server/index.js
Environment=STEPBOOK_DATA_DIR=$DATA_DIR
Environment=PORT=3001
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ── 9. Enable and restart service ───────────────────────────────────────────
echo "==> Enabling and (re)starting stepbook service..."
systemctl daemon-reload
systemctl enable --now stepbook
systemctl restart stepbook
echo "==> Service is running."

# ── 10. Configure tailscale serve ───────────────────────────────────────────
echo "==> Configuring tailscale serve (HTTPS :443 -> localhost:3001)..."
tailscale serve --bg --https=443 http://localhost:3001

# ── 11. Print access URL ────────────────────────────────────────────────────
TS_HOSTNAME=$(tailscale status --json | grep -oP '"DNSName"\s*:\s*"\K[^"]+' | head -1 | sed 's/\.$//')
if [ -n "$TS_HOSTNAME" ]; then
  echo ""
  echo "============================================"
  echo "  Stepbook is live at:"
  echo "  https://$TS_HOSTNAME"
  echo "============================================"
else
  echo ""
  echo "==> Stepbook service is running on port 3001."
  echo "    Could not determine Tailscale hostname."
  echo "    Run 'tailscale status' to find your device name."
fi
