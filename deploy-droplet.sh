#!/bin/bash

### CONFIGURABLE VARIABLES ###
PROJECT_NAME="mobile-profit-bot"
REPO_URL="git@github.com:rich-strain/sites-payload.mobileprofitbot.git"
PAYLOAD_VERSION="3.54.0"
APP_PORT=3000
DOMAIN="sites-payload.mobileprofitbot.com"
USE_NGINX=true

### Colors for output ###
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting Payload CMS deployment...${NC}"

# Step 1: Update and install base packages
apt update && apt upgrade -y
apt install -y build-essential curl git ufw nginx

# Step 2: Add swap memory (2GB)
if [ ! -f /swapfile ]; then
  echo -e "${GREEN}🧠 Adding 2GB swap memory...${NC}"
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
else
  echo -e "${GREEN}🧠 Swap file already exists. Skipping swap setup.${NC}"
fi

# Step 3: Install latest LTS Node.js using 'n'
if command -v node > /dev/null 2>&1; then
  echo -e "${GREEN}🟢 Node.js is already installed. Skipping installation.${NC}"
else
  echo -e "${GREEN}📦 Installing latest LTS Node.js...${NC}"
  curl -fsSL https://raw.githubusercontent.com/tj/n/master/bin/n | bash -s lts
  export PATH="/usr/local/bin:$PATH"
fi

# Step 4: Install global Node tools
npm install -g pnpm pm2

# Step 5: Clone or update project
cd /root

if [ -d "$PROJECT_NAME" ]; then
  echo -e "${GREEN}📁 Project exists. Pulling latest changes...${NC}"
  cd "$PROJECT_NAME"
  git pull
else
  echo -e "${GREEN}📁 Cloning project from GitHub...${NC}"
  git clone "$REPO_URL" "$PROJECT_NAME"
  cd "$PROJECT_NAME"
fi

# Step 6: Create .env file if missing
if [ -f ".env" ]; then
  echo -e "${GREEN}⚙️ .env file already exists. Skipping creation.${NC}"
else
  echo -e "${GREEN}⚙️ Creating new .env file...${NC}"
  cat <<EOF > .env
PAYLOAD_SECRET=$(openssl rand -hex 32)
MONGODB_URI=mongodb://localhost:27017/${PROJECT_NAME}
PORT=$APP_PORT
NODE_ENV=production
SERVER_URL=https://$DOMAIN
EOF
fi

# Step 7: Install project dependencies
pnpm install

# Step 8: Build project (log output to file)
echo -e "${GREEN}🔧 Building Next.js app. This may take a few minutes...${NC}"
pnpm run build | tee /root/build.log

# Step 9: Start app with PM2 in the project directory
pm2 delete payload || true
pm2 start pnpm --name payload --cwd /root/"$PROJECT_NAME" -- run start
pm2 startup
pm2 save

# Step 10: Configure UFW firewall
ufw allow OpenSSH
ufw allow "$APP_PORT"
ufw --force enable

# Step 11: NGINX Reverse Proxy
if [ "$USE_NGINX" = true ] && [ -n "$DOMAIN" ]; then
  echo -e "${GREEN}🌐 Setting up NGINX for $DOMAIN...${NC}"

  NGINX_CONF="/etc/nginx/sites-available/payload"

  if [ ! -f "$NGINX_CONF" ]; then
    cat <<EOF > "$NGINX_CONF"
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    ln -s "$NGINX_CONF" /etc/nginx/sites-enabled/
    nginx -t && systemctl restart nginx
  else
    echo -e "${GREEN}🔁 NGINX config already exists. Skipping creation.${NC}"
  fi

  # Step 12: Certbot SSL
  echo -e "${GREEN}🔒 Installing SSL via Certbot...${NC}"
  apt install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN
else
  echo -e "${GREEN}🌍 Skipping NGINX setup. App available at port $APP_PORT${NC}"
fi

# ✅ Final Output
echo -e "${GREEN}✅ Payload CMS deployed successfully!${NC}"
if [ -n "$DOMAIN" ]; then
  echo "→ Admin Panel: https://$DOMAIN/admin"
else
  echo "→ Admin Panel: http://your_server_ip:$APP_PORT/admin"
fi