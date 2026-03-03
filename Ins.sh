#!/bin/bash

# ==========================================
# SDGAMER - SKA HOSTING
# Pterodactyl + Telebit Auto-Installer
# ==========================================

# --- 1. CONFIGURATION ---
# Default credentials
USER_EMAIL="admin@skahosting.com"
USER_PASS="Password123!"  # <--- Login Password
# Note: Panel URL will be updated by Telebit later

# Colors
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# Clear & Banner
clear
echo -e "${CYAN}"
echo "   _____ ____  _____          __  __ ______ ____  "
echo "  / ____|  _ \|  __ \   /\   |  \/  |  ____|  _ \ "
echo " | (___ | | | | |  | | /  \  | \  / | |__  | |_) |"
echo "  \___ \| | | | |  | |/ /\ \ | |\/| |  __| |  _ < "
echo "  ____) | |_| | |__| / ____ \| |  | | |____| |_) |"
echo " |_____/|____/|_____/_/    \_\_|  |_|______|____/ "
echo -e "${NC}"
echo -e "${GREEN}   TELEBIT EDITION - NO PORTS NEEDED!    ${NC}"
echo "=================================================="
sleep 2

# --- 2. SYSTEM PREP ---
echo -e "${CYAN}[1/8] Updating System & Branding...${NC}"

# SELinux Permissive (Important for Fedora)
sudo setenforce 0
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/g' /etc/selinux/config

# Updates
sudo dnf update -y
sudo dnf install -y git curl tar unzip wget policycoreutils-python-utils cronie

# SDGAMER Branding
if ! grep -q "SDGAMER" ~/.bashrc; then
    echo 'export PS1="\[\e[1;32m\]┌──(\[\e[1;36m\]SDGAMER㉿SKA-HOSTING\[\e[1;32m\])-[\[\e[0;37m\]\w\[\e[1;32m\]]\n\[\e[1;32m\]└─\[\e[1;31m\]# \[\e[0m\]"' >> ~/.bashrc
fi

# --- 3. INSTALL STACK ---
echo -e "${CYAN}[2/8] Installing MariaDB, Redis, Nginx...${NC}"
sudo dnf install -y mariadb-server redis nginx
sudo systemctl enable --now mariadb redis nginx

# Database Setup
echo -e "${CYAN}Creating Database...${NC}"
sudo mysql -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$USER_PASS';"
sudo mysql -e "CREATE DATABASE panel;"
sudo mysql -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
sudo mysql -e "FLUSH PRIVILEGES;"

# --- 4. INSTALL PHP ---
echo -e "${CYAN}[3/8] Installing PHP 8.2...${NC}"
sudo dnf module reset php -y
sudo dnf module enable php:8.2 -y
sudo dnf install -y php php-cli php-gd php-mysqlnd php-pdo php-mbstring php-tokenizer php-bcmath php-xml php-fpm php-curl php-zip php-intl php-json

# Fix PHP-FPM User
sudo sed -i 's/user = apache/user = nginx/g' /etc/php-fpm.d/www.conf
sudo sed -i 's/group = apache/group = nginx/g' /etc/php-fpm.d/www.conf
sudo systemctl restart php-fpm

# --- 5. INSTALL PANEL ---
echo -e "${CYAN}[4/8] Installing Pterodactyl Panel...${NC}"
sudo mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
sudo curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
sudo tar -xzvf panel.tar.gz
sudo chmod -R 755 storage/* bootstrap/cache/

# Composer
sudo curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
sudo cp .env.example .env
sudo composer install --no-dev --optimize-autoloader

# Generate Key
sudo php artisan key:generate --force

# --- 6. CONFIGURE PANEL ---
echo -e "${CYAN}[5/8] Configuring Panel...${NC}"
# Using localhost temporarily, we will update it with Telebit URL later
sudo php artisan p:environment:setup --author="$USER_EMAIL" --url="http://localhost" --timezone="Asia/Kolkata" --cache="redis" --session="redis" --queue="redis" --redis-host="127.0.0.1" --redis-pass="" --redis-port="6379" --settings-ui=true
sudo php artisan p:database:setup --host="127.0.0.1" --port="3306" --database="panel" --username="pterodactyl" --password="$USER_PASS"

# Migrate & Create User
sudo php artisan migrate --seed --force
sudo php artisan p:user:make --email="$USER_EMAIL" --admin=1 --password="$USER_PASS" --username="admin" --name_first="SDGAMER" --name_last="Admin"
sudo chown -R nginx:nginx /var/www/pterodactyl

# --- 7. WORKERS & NGINX ---
echo -e "${CYAN}[6/8] Finalizing Nginx...${NC}"

# Queue Worker
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

# Nginx Config
sudo bash -c 'cat > /etc/nginx/conf.d/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name _;
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
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --reload

# --- 8. TELEBIT SETUP ---
echo -e "${CYAN}[7/8] Installing Telebit Tunnel...${NC}"
curl https://get.telebit.io/ | bash

# Enable Telebit HTTP Tunnel on Port 80
echo -e "${YELLOW}Configuring Telebit for Port 80...${NC}"
~/telebit http 80
~/telebit save

# Get the URL
TB_URL=$(~/telebit status | grep -o 'https://.*\.telebit\.io')

# Update Pterodactyl with Telebit URL
if [ ! -z "$TB_URL" ]; then
    echo -e "${GREEN}Telebit URL Found: $TB_URL${NC}"
    echo -e "${YELLOW}Updating Panel Configuration...${NC}"
    sed -i "s|APP_URL=.*|APP_URL=$TB_URL|g" /var/www/pterodactyl/.env
    # Clear cache to apply changes
    cd /var/www/pterodactyl
    php artisan config:clear
    php artisan cache:clear
    php artisan view:clear
else
    echo -e "${RED}Could not auto-detect Telebit URL. You can see it below.${NC}"
fi

# --- DONE ---
source ~/.bashrc 2>/dev/null
echo ""
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   INSTALLATION COMPLETE - TELEBIT MODE       ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "Your Panel URL: ${YELLOW}$TB_URL${NC}"
echo -e "(If URL is empty, check Telebit status below)"
echo -e "Admin Email   : ${YELLOW}$USER_EMAIL${NC}"
echo -e "Password      : ${YELLOW}$USER_PASS${NC}"
echo -e "----------------------------------------------"
echo -e "NOTE: Telebit runs in the background. Enjoy!"
echo ""
~/telebit status
