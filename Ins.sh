#!/bin/bash

# ==========================================
# SDGAMER - SKA HOSTING
# Pterodactyl Installer for Fedora (RedHat)
# ==========================================

# 1. Colors & Banner
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# 2. User Inputs
echo -e "${YELLOW}Enter Installation Details:${NC}"
read -p "Admin Email: " USER_EMAIL
read -p "Admin Password (for Panel & DB): " USER_PASS
read -p "Panel URL (e.g., https://panel.example.com): " PANEL_URL
read -p "Cloudflare Tunnel Token (Press Enter to skip if manual): " CF_TOKEN

# 3. System Prep
echo -e "${CYAN}[1/8] Updating System & Disabling SELinux Enforcement...${NC}"
sudo setenforce 0
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/g' /etc/selinux/config
sudo dnf update -y
sudo dnf install -y git curl tar unzip wget policycoreutils-python-utils cronie

# 4. Install Core Services
echo -e "${CYAN}[2/8] Installing MariaDB, Redis, and Nginx...${NC}"
sudo dnf install -y mariadb-server redis nginx
sudo systemctl enable --now mariadb redis nginx

# Database Setup
echo -e "${CYAN}Creating Database...${NC}"
sudo mysql -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$USER_PASS';"
sudo mysql -e "CREATE DATABASE panel;"
sudo mysql -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
sudo mysql -e "FLUSH PRIVILEGES;"

# 5. Install PHP 8.2
echo -e "${CYAN}[3/8] Installing PHP 8.2...${NC}"
sudo dnf module reset php -y
sudo dnf module enable php:8.2 -y
sudo dnf install -y php php-cli php-gd php-mysqlnd php-pdo php-mbstring php-tokenizer php-bcmath php-xml php-fpm php-curl php-zip php-intl php-json

# Fix PHP-FPM User (Change Apache to Nginx for Fedora)
sudo sed -i 's/user = apache/user = nginx/g' /etc/php-fpm.d/www.conf
sudo sed -i 's/group = apache/group = nginx/g' /etc/php-fpm.d/www.conf
sudo systemctl restart php-fpm

# 6. Install Pterodactyl Panel
echo -e "${CYAN}[4/8] Downloading Pterodactyl Panel...${NC}"
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

# 7. Configure Panel
echo -e "${CYAN}[5/8] Configuring Panel Data...${NC}"
sudo php artisan p:environment:setup --author="$USER_EMAIL" --url="$PANEL_URL" --timezone="Asia/Kolkata" --cache="redis" --session="redis" --queue="redis" --redis-host="127.0.0.1" --redis-pass="" --redis-port="6379" --settings-ui=true
sudo php artisan p:database:setup --host="127.0.0.1" --port="3306" --database="panel" --username="pterodactyl" --password="$USER_PASS"

# Migrate DB
sudo php artisan migrate --seed --force

# Create Admin User
sudo php artisan p:user:make --email="$USER_EMAIL" --admin=1 --password="$USER_PASS" --username="admin" --name_first="SDGAMER" --name_last="Admin"

# Set Permissions
sudo chown -R nginx:nginx /var/www/pterodactyl

# 8. Queue Worker Setup
echo -e "${CYAN}[6/8] Setting up Background Workers...${NC}"
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

# 9. Nginx Configuration
echo -e "${CYAN}[7/8] Configuring Nginx Web Server...${NC}"
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

# 10. Cloudflared Setup
echo -e "${CYAN}[8/8] Setting up Cloudflare Tunnel...${NC}"
sudo dnf config-manager --add-repo https://pkg.cloudflare.com/cloudflared-ascii.repo
sudo dnf install cloudflared -y

# Firewall Rules
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --add-service=https --permanent
sudo firewall-cmd --reload

if [ -z "$CF_TOKEN" ]; then
    echo -e "${RED}Skipping Cloudflared auto-connect (No token provided).${NC}"
else
    echo -e "${GREEN}Connecting to Cloudflare...${NC}"
    sudo cloudflared service install "$CF_TOKEN"
    sudo systemctl start cloudflared
    sudo systemctl enable cloudflared
fi

# Final Message
echo ""
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}   INSTALLATION COMPLETE - SDGAMER SCRIPT     ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "Panel URL: ${YELLOW}$PANEL_URL${NC}"
echo -e "Email:     ${YELLOW}$USER_EMAIL${NC}"
echo -e "Password:  ${YELLOW}$USER_PASS${NC}"
echo -e "----------------------------------------------"
if [ -z "$CF_TOKEN" ]; then
    echo -e "${RED}IMPORTANT: You must run 'cloudflared tunnel run' manually!${NC}"
fi
echo -e "Enjoy your SKA HOSTING Panel!"
