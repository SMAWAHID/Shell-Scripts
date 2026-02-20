#!/bin/bash

set -e

echo "===== GPU Deployment Script ====="

# ===============================
# GITHUB AUTH INPUT
# ===============================

read -p "Enter Backend GitHub repository (owner/repo): " BACKEND_REPO_PATH
read -p "Enter Frontend GitHub repository (owner/repo): " FRONTEND_REPO_PATH

read -p "Enter GitHub username: " GITHUB_USER
read -s -p "Enter GitHub PAT (hidden): " GITHUB_PAT
echo ""

# ===============================
# PROJECT CONFIG
# ===============================

read -p "Enter backend folder name (default: backend): " BACKEND_DIR
BACKEND_DIR=${BACKEND_DIR:-backend}

read -p "Enter frontend folder name (default: frontend): " FRONTEND_DIR
FRONTEND_DIR=${FRONTEND_DIR:-frontend}

read -p "Enter backend port (default: 8000): " BACKEND_PORT
BACKEND_PORT=${BACKEND_PORT:-8000}

read -p "Enter frontend port (default: 3000): " FRONTEND_PORT
FRONTEND_PORT=${FRONTEND_PORT:-3000}

NODE_VERSION="v20.11.1"

echo "Updating system..."
apt update
apt install -y python3 python3-venv python3-pip git curl build-essential

# ===============================
# INSTALL NODE
# ===============================

if ! command -v node &> /dev/null
then
    echo "Installing Node..."
    curl -L https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz -o node.tar.xz
    tar -xf node.tar.xz
    mv node-${NODE_VERSION}-linux-x64 /usr/local/node
    export PATH=$PATH:/usr/local/node/bin
    echo 'export PATH=$PATH:/usr/local/node/bin' >> ~/.bashrc
fi

# ===============================
# INSTALL PM2
# ===============================

if ! command -v pm2 &> /dev/null
then
    npm install -g pm2
fi

# ===============================
# CLONE REPOSITORIES
# ===============================

echo "Cloning backend..."
if [ ! -d "$BACKEND_DIR" ]; then
    git clone https://${GITHUB_USER}:${GITHUB_PAT}@github.com/${BACKEND_REPO_PATH}.git $BACKEND_DIR
fi

echo "Cloning frontend..."
if [ ! -d "$FRONTEND_DIR" ]; then
    git clone https://${GITHUB_USER}:${GITHUB_PAT}@github.com/${FRONTEND_REPO_PATH}.git $FRONTEND_DIR
fi

# Clear sensitive variable
unset GITHUB_PAT

# ===============================
# BACKEND SETUP
# ===============================

echo "Setting up backend..."
cd $BACKEND_DIR

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt
pip install "transformers==4.47.1" "diffusers==0.32.2" "huggingface_hub>=0.26.0"

cd ..

# ===============================
# FRONTEND SETUP
# ===============================

echo "Setting up frontend..."
cd $FRONTEND_DIR

npm install
npm run build

cd ..

# ===============================
# START SERVICES
# ===============================

pm2 delete all || true

echo "Starting backend..."
pm2 start $BACKEND_DIR/venv/bin/uvicorn \
    --name gpu-backend \
    -- main:app --host 0.0.0.0 --port $BACKEND_PORT

echo "Starting frontend..."
pm2 start npm \
    --name gpu-frontend \
    --prefix $FRONTEND_DIR -- run preview -- --host 0.0.0.0 --port $FRONTEND_PORT

pm2 save

echo "===== Deployment Complete ====="
echo "Backend running on port $BACKEND_PORT"
echo "Frontend running on port $FRONTEND_PORT"
echo "Expose ports in RunPod networking panel."
