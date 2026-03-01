#!/bin/bash

# --- VISUAL SETUP ---
echo -e "\e[1;36m"
echo "==================================================="
echo "    SKA HOSTING INSTALLER - CLOUDFLARE EDITION     "
echo "             Created by SDGAMER                    "
echo "==================================================="
echo -e "\e[0m"
sleep 2

# 1. ROOT CHECK
if [ "$EUID" -ne 0 ]; then 
  echo -e "\e[1;31mPlease run as root (sudo su)\e[0m"
  exit
fi

# 2. UPDATE SYSTEM
echo "[+] Updating System & Installing Essentials..."
apt update -y && apt upgrade -y
apt install -y curl git zip unzip

# 3. INSTALL DOCKER
if ! command -v docker &> /dev/null; then
    echo "[+] Installing Docker Engine..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
else
    echo "[!] Docker already installed."
fi

# 4. INSTALL NODE.JS 20
if ! command -v node &> /dev/null; then
    echo "[+] Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
fi

# 5. SETUP PANEL
echo "[+] Setting up SKA HOSTING..."
# (Agar purana folder hai to delete karo taaki fresh install ho)
rm -rf ska-hosting
# --- YAHAN APNA GITHUB LINK DALNA ---
git clone https://github.com/sdgamer8263-sketch/ska-hosting.git
cd ska-hosting
npm install

# 6. CLOUDFLARE TUNNEL SETUP
echo ""
echo "======================================================"
echo " CLOUDFLARE TUNNEL CONFIGURATION"
echo " 1. Go to https://one.dash.cloudflare.com/"
echo " 2. Networks -> Tunnels -> Create Tunnel"
echo " 3. Select 'Debian' -> Copy the connector command."
echo "    (It looks like: cloudflared service install eyJh...)"
echo "======================================================"
echo -e "\e[1;33mPaste the Cloudflare Token (starts with eyJh...): \e[0m"
read CF_TOKEN

if [ -z "$CF_TOKEN" ]; then
    echo "[-] No token provided. Panel will run on IP:8080 only."
else
    echo "[+] Installing Cloudflared..."
    # Download Cloudflared
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i cloudflared.deb
    
    # Run Service
    echo "[+] Authenticating Tunnel..."
    cloudflared service install $CF_TOKEN
    
    echo -e "\e[1;32m[+] Cloudflare Tunnel Active! Check your domain.\e[0m"
fi

# 7. START PANEL
echo ""
echo "Installation Complete! Starting Panel..."
# Run in background using PM2 or nohup (Use nohup for simple usage)
nohup node index.js > panel.log 2>&1 &

echo -e "\e[1;32mSKA HOSTING is now running in background!\e[0m"
echo "Check your domain or http://IP:8080"
