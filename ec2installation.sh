#!/usr/bin/env bash
set -euo pipefail

# EC2 setup: node, pm2, caddy, python3 venv + pip
# Target: Ubuntu 22.04 / 24.04. Run as a sudo-capable user (not root).

echo ">>> Updating apt"
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg debian-keyring debian-archive-keyring apt-transport-https

# ---------- Node.js (22 LTS via NodeSource) ----------
echo ">>> Installing Node.js 22 LTS"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
node -v && npm -v

# ---------- PM2 ----------
echo ">>> Installing PM2"
sudo npm install -g pm2
# Wire PM2 into systemd so apps survive reboots.
# This prints/sets up the systemd unit for the current user.
sudo env PATH="$PATH" pm2 startup systemd -u "$USER" --hp "$HOME"
pm2 -v

# ---------- Caddy (official repo) ----------
echo ">>> Installing Caddy"
if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y caddy
fi
caddy version
sudo systemctl enable --now caddy

# ---------- Python3 venv + pip ----------
echo ">>> Installing Python3 venv + pip"
sudo apt-get install -y python3 python3-venv python3-pip
python3 --version && pip3 --version

echo ">>> Done."
echo "Next:"
echo "  - Run 'pm2 save' after starting your apps to persist the process list."
echo "  - Edit /etc/caddy/Caddyfile then 'sudo systemctl reload caddy'."
echo "  - Create a venv with: python3 -m venv .venv && source .venv/bin/activate"
