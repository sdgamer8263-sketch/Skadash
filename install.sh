#!/bin/bash

# Logo & Branding
echo "======================================="
echo "   SKA HOSTING INSTALLER - CLOUDFLARE  "
echo "        Created by SDGAMER             "
echo "======================================="
sleep 2

# 1. Update System
sudo apt update -y && sudo apt upgrade -y

# 2. Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
fi

# 3. Install Node.js
if ! command -v node &> /dev/null; then
    echo "Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# 4. Clone Repo
git clone https://github.com/sdgamer8263-sketch/ska-hosting.git
cd ska-hosting
npm install

# 5. Cloudflared Setup (Subdomain Logic)
echo ""
echo "----------------------------------------------------"
echo " CLOUDFLARE TUNNEL SETUP"
echo " 1. Go to https://one.dash.cloudflare.com/"
echo " 2. Create a Tunnel -> Choose Debian/Ubuntu"
echo " 3. Copy the token (starts with eyJh...)"
echo "----------------------------------------------------"
read -p "Paste your Cloudflare Tunnel Token here: " CF_TOKEN

if [ -z "$CF_TOKEN" ]; then
  echo "Skipping Cloudflare setup (Localhost only)..."
else
  echo "Installing Cloudflared..."
  curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
  sudo dpkg -i cloudflared.deb
  sudo cloudflared service install $CF_TOKEN
  echo "Cloudflare Tunnel Activated!"
fi

# 6. Start Panel
echo "SKA HOSTING Installed Successfully!"
node index.js
