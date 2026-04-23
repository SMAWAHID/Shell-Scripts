#!/bin/bash

set -e  # stop script on error

echo "🚀 Starting deployment..."

# -------------------------------
# 1. Install Node.js (if missing)
# -------------------------------
if ! command -v node &> /dev/null
then
    echo "📦 Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
else
    echo "✅ Node.js already installed"
fi

# -------------------------------
# 2. Install PM2 (if missing)
# -------------------------------
if ! command -v pm2 &> /dev/null
then
    echo "📦 Installing PM2..."
    sudo npm install -g pm2
else
    echo "✅ PM2 already installed"
fi

# -------------------------------
# 3. Install Caddy (if missing)
# -------------------------------
if ! command -v caddy &> /dev/null
then
    echo "📦 Installing Caddy..."
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update
    sudo apt install -y caddy
else
    echo "✅ Caddy already installed"
fi

# -------------------------------
# 4. Install dependencies
# -------------------------------
echo "📦 Installing project dependencies..."
npm install

# -------------------------------
# 5. Build project
# -------------------------------
read -p "⚙️ Build command (default: npm run build): " BUILD_CMD
BUILD_CMD=${BUILD_CMD:-npm run build}

echo "🏗 Running build..."
eval $BUILD_CMD

# -------------------------------
# 6. Start with PM2
# -------------------------------
read -p "🧠 Enter PM2 process name: " APP_NAME
read -p "⚙️ Start command (e.g. npm start or serve -s dist): " START_CMD

echo "🚀 Starting app with PM2..."
pm2 start $START_CMD --name $APP_NAME

pm2 save

# -------------------------------
# 7. Setup Caddy reverse proxy
# -------------------------------
read -p "🌐 Enter domain (e.g. app.example.com): " DOMAIN
read -p "🔌 Enter app port (e.g. 3000): " PORT

CADDYFILE="/etc/caddy/Caddyfile"

echo "⚙️ Configuring Caddy..."

sudo bash -c "cat >> $CADDYFILE" <<EOL

$DOMAIN {
    reverse_proxy localhost:$PORT
}
EOL

# Reload Caddy
sudo systemctl reload caddy

echo "🎉 Deployment complete!"
echo "🌍 Your app should be live at: https://$DOMAIN"
