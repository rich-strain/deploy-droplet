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

echo -e "${GREEN}Starting Payload CMS deployment...${NC}"

# Step 1: Update and install dependencies
apt update && apt upgrade -y
apt install -y build-essential curl git ufw nginx

# Step 2: Install Node.js LTS
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# Step 3: Install PNPM and PM2
npm install -g pnpm pm2

# Step 4: Clone Payload CMS project
cd /root

if [ -n "$REPO_URL" ]; then
  if [ -d "$PROJECT_NAME" ]; then
    echo -e "${GREEN}Project directory already exists. Skipping clone.${NC}"
  else
    git clone "$REPO_URL" "$PROJECT_NAME"
  fi
else
  npx create-payload-app@$PAYLOAD_VERSION "$PROJECT_NAME" --yes
fi

cd "$PROJECT_NAME"

# Step 5: Create .env file if it doesn't exist
# if [ -f ".env" ]; then
#   echo -e "${GREEN}.env file already exists. Skipping creation.${NC}"
# else
#   cat <<EOF > .env
# PAYLOAD_SECRET=$(openssl rand -hex 32)
# MONGODB_URI=mongodb://localhost:27017/${PROJECT_NAME}
# PORT=$APP_PORT
# NODE_ENV=production
# SERVER_URL=https://$DOMAIN
# EOF
# fi

# Step 6: Install Node dependencies
pnpm install

# Step 7: Build the app
pnpm run build

# Step 8: Start with PM2 using the start script from package.json
pm2 start pnpm --name payload -- run start
pm2 startup
pm2 save

# Step 9: Configure UFW firewall
ufw allow OpenSSH
ufw allow "$APP_PORT"
ufw --force enable

# Step 10: Set up NGINX reverse proxy
if [ "$USE_NGINX" = true ] && [ -n "$DOMAIN" ]; then
  echo -e "${GREEN}Setting up Nginx for $DOMAIN...${NC}"

  NGINX_CONF="/etc/nginx/sites-available/payload"

  if [ -f "$NGINX_CONF" ]; then
    echo -e "${GREEN}Nginx config already exists. Skipping creation.${NC}"
  else
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
  fi

  # Step 11: SSL with Certbot
  echo -e "${GREEN}Installing Certbot for HTTPS...${NC}"
  apt install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN
else
  echo -e "${GREEN}Skipping Nginx setup. App running on port $APP_PORT${NC}"
fi

# Final output
echo -e "${GREEN}✅ Payload CMS deployed successfully!${NC}"
if [ -n "$DOMAIN" ]; then
  echo "→ Visit: https://$DOMAIN/admin"
else
  echo "→ Visit: http://your_server_ip:$APP_PORT/admin"
fi

