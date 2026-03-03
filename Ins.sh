#!/bin/bash

# ==========================================
# SDGAMER - SKA HOSTING
# Pterodactyl Installer for Fedora
# ==========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Clear Screen & Show Intro
clear
echo -e "${CYAN}"
echo "   _____ ____  _____          __  __ ______ ____  "
echo "  / ____|  _ \|  __ \   /\   |  \/  |  ____|  _ \ "
echo " | (___ | | | | |  | | /  \  | \  / | |__  | |_) |"
echo "  \___ \| | | | |  | |/ /\ \ | |\/| |  __| |  _ < "
echo "  ____) | |_| | |__| / ____ \| |  | | |____| |_) |"
echo " |_____/|____/|_____/_/    \_\_|  |_|______|____/ "
echo -e "${NC}"
echo -e "${GREEN}       Automated Installer by SDGAMER       ${NC}"
echo "=================================================="
sleep 2

# --- USER INPUTS ---
echo -e "${YELLOW}Enter Installation Details:${NC}"
read -p "Admin Email: " USER_EMAIL
read -p "Admin Password (for Panel & DB): " USER_PASS
read -p "Panel URL (e.g., https://panel.skahosting.com): " PANEL_URL
read -p "Cloudflare Tunnel Token (Press Enter to skip if manual): " CF_TOKEN

# --- 1. SYSTEM PREP & BRANDING ---
echo -e "${CYAN}[1/9] Setting up SDGAMER Branding & System Updates...${NC}"

# Set SELinux to Permissive (Crucial for Fedora)
sudo setenforce 0
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/g' /etc/selinux/config

# Update System
sudo dnf update -y
sudo dnf install -y git curl tar unzip wget policycoreutils-python-utils cronie

# Apply SDGAMER Terminal Prompt (The Hacker Look)
if ! grep -q "SDGAMER" ~/.bashrc; then
    echo 'export PS1="\[\e[1;32m\]┌──(\[\e[1;36m\]SDGAMER㉿SKA-HOSTING\[\e[1;32m\])-[\[\e[0;37m\]\w\[\e[1;32m\]]\n\[\e[1;32m\]└─\[\e[1;31m\]# \[\e[0m\]"' >> ~/.bashrc
fi

# Apply Login Banner (MOTD)
cat > /etc/profile.d/sdgamer_banner.sh <<EOF
#!/bin/bash
CYAN='\033[1;36m'
GREEN='\033[1;32m'
NC='\033[0m'
clear
echo -e "\${CYAN}"
echo "  SDGAMER - SKA HOSTING SERVER  "
echo "  Status: ONLINE | OS: Fedora   "
echo -e "\${NC}"
echo -e "\${GREEN}  Welcome Back, Boss! Ready to Host. \${NC}"
echo ""
EOF
chmod +x /etc/profile.d/sdgamer_banner.sh

# --- 2. INSTALL STACK ---
echo -e "${CYAN}[2/9] Installing MariaDB, Redis, and Nginx...${NC}"
sudo dnf install -y mariadb-server redis nginx
sudo systemctl enable --now mariadb redis nginx

# Create Database
echo -e "${CYAN}Configuring Database...${NC}"
sudo mysql -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$USER_PASS';"
sudo mysql -e "CREATE DATABASE panel;"
sudo mysql -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
sudo mysql -e "FLUSH PRIVILEGES;"

# --- 3. INSTALL PHP ---
echo -e "${CYAN}[3/9] Installing PHP 8.2...${NC}"
sudo dnf module reset php -y
sudo dnf module enable php:8.2 -y
sudo dnf install -y php php-cli php-gd php-mysqlnd php-pdo php-mbstring php-tokenizer php-bcmath php-xml php-fpm php-curl php-zip php-intl php-json

# FIX PHP-FPM USER (Fedora defaults to apache, we need nginx)
sudo sed -i 's/user = apache/user = nginx/g' /etc/php-fpm.d/www.conf
sudo sed -i 's/group = apache/group = nginx/g' /etc/php-fpm.d/www.conf
sudo systemctl restart php-fpm

# --- 4. INSTALL PANEL ---
echo -e "${CYAN}[4/9] Downloading Pterodactyl Panel...${NC}"
sudo mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
sudo curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
sudo tar -xzvf panel.tar.gz
sudo chmod -R 755 storage/* bootstrap/cache/

# Composer Install
echo -e "${CYAN}Running Composer...${NC}"
sudo curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
sudo cp .env.example .env
sudo composer install --no-dev --optimize-autoloader

# Generate Key
sudo php artisan key:generate --force

# --- 5. CONFIGURE PANEL ---
echo -e "${CYAN}[5/9] Configuring Panel Settings...${NC}"
sudo php artisan p:environment:setup --author="$USER_EMAIL" --url="$PANEL_URL" --timezone="Asia/Kolkata" --cache="redis" --session="redis" --queue="redis" --redis-host="127.0.0.1" --redis-pass="" --redis-port="6379" --settings-ui=true
sudo php artisan p:database:setup --host="127.0.0.1" --port="3306" --database="panel" --username="pterodactyl" --password="$USER_PASS"

# Migrate DB
sudo php artisan migrate --seed --force

# Create Admin User
sudo php artisan p:user:make --email="$USER_EMAIL" --admin=1 --password="$USER_PASS" --username="admin" --name_first="SDGAMER" --name_last="Admin"

# Set Permissions
sudo chown -R nginx:nginx /var/www/pterodactyl

# --- 6. WORKERS SETUP ---
echo -e "${CYAN}[6/9] Setting up Background Workers...${NC}"
(sudo crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | sudo crontab -u nginx -

sudo bash -c 'cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis.service
[Service]
User=nginx
Group=nginx
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
[Install]
WantedBy=multi-user.target
EOF'

sudo systemctl enable --now pteroq

# --- 7. NGINX SETUP ---
echo -e "${CYAN}[7/9] Configuring Nginx Web Server...${NC}"
sudo bash -c 'cat > /etc/nginx/conf.d/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name localhost;
    root /var/www/pterodactyl/public;
    index index.php;
    charset utf-8;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }
}
EOF'
sudo systemctl restart nginx

# --- 8. CLOUDFLARED SETUP ---
echo -e "${CYAN}[8/9] Setting up Cloudflare Tunnel...${NC}"
sudo dnf config-manager --add-repo https://pkg.cloudflare.com/cloudflared-ascii.repo
sudo dnf install cloudflared -y

# Firewall Setup
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --add-service=https --permanent
sudo firewall-cmd --reload

if [ -z "$CF_TOKEN" ]; then
    echo -e "${RED}Skipping Cloudflared auto-connect (No token provided).${NC}"
else
    echo -e "${GREEN}Connecting to Cloudflare...${NC}"
    # Uninstall old service if exists to avoid conflict
    sudo cloudflared service uninstall 2>/dev/null
    sudo cloudflared service install "$CF_TOKEN"
    sudo systemctl start cloudflared
    sudo systemctl enable cloudflared
fi

# --- 9. FINAL TOUCH ---
# Refresh bashrc for immediate effect (might need re-login)
source ~/.bashrc 2>/dev/null

echo ""
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   INSTALLATION COMPLETE - SDGAMER STYLE      ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "Panel URL: ${YELLOW}$PANEL_URL${NC}"
echo -e "Email:     ${YELLOW}$USER_EMAIL${NC}"
echo -e "Password:  ${YELLOW}$USER_PASS${NC}"
echo -e "----------------------------------------------"
echo -e "${CYAN}Please logout and login again to see your new Terminal Banner!${NC}"
