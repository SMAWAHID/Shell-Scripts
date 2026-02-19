#!/bin/bash

set -e

echo "===== GPU Deployment Script ====="

read -p "Enter Backend GitHub repository URL: " BACKEND_REPO
read -p "Enter Frontend GitHub repository URL: " FRONTEND_REPO

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

# ===== INSTALL NODE =====
if ! command -v node &> /dev/null
then
    echo "Installing Node..."
    curl -L https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz -o node.tar.xz
    tar -xf node.tar.xz
    mv node-${NODE_VERSION}-linux-x64 /usr/local/node
    export PATH=$PATH:/usr/local/node/bin
    echo 'export PATH=$PATH:/usr/local/node/bin' >> ~/.bashrc
fi

# ===== INSTALL PM2 =====
if ! command -v pm2 &> /dev/null
then
    npm install -g pm2
fi

# ===== CLONE BACKEND =====
if [ ! -d "$BACKEND_DIR" ]; then
    git clone $BACKEND_REPO $BACKEND_DIR
fi

# ===== CLONE FRONTEND =====
if [ ! -d "$FRONTEND_DIR" ]; then
    git clone $FRONTEND_REPO $FRONTEND_DIR
fi

# ===== BACKEND SETUP =====
echo "Setting up backend..."
cd $BACKEND_DIR

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt

# Transformers compatibility fix
pip install "transformers==4.47.1" "diffusers==0.32.2" "huggingface_hub>=0.26.0"

cd ..

# ===== FRONTEND SETUP =====
echo "Setting up frontend..."
cd $FRONTEND_DIR

npm install
npm run build

cd ..

# ===== START SERVICES =====
pm2 delete all || true

echo "Starting backend..."
pm2 start "$BACKEND_DIR/venv/bin/uvicorn main:app --host 0.0.0.0 --port $BACKEND_PORT" --name gpu-backend

echo "Starting frontend..."
pm2 start "cd $FRONTEND_DIR && npm run preview -- --host 0.0.0.0 --port $FRONTEND_PORT" --name gpu-frontend

pm2 save

echo "===== Deployment Complete ====="
echo "Backend running on port $BACKEND_PORT"
echo "Frontend running on port $FRONTEND_PORT"
echo "Use RunPod networking panel to access exposed ports."
