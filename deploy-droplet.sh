SHELL SCRIPT DIGITAL OCEAN DROPLET  #!/bin/bash

### CONFIGURABLE VARIABLES ###
PROJECT_NAME="payload-app"
REPO_URL=""  # Leave blank to scaffold a fresh Payload CMS project
PAYLOAD_VERSION="3.54.0"
APP_PORT=3000
DOMAIN=“sites-payload.mobileprofitbot.com"
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

# Step 3: Install MongoDB
#apt install -y mongodb
#systemctl enable mongodb
#systemctl start mongodb

# Step 4: Install PM2
npm install -g pm2

# Step 5: Clone or scaffold Payload CMS project
cd /root

if [ -n "$REPO_URL" ]; then
  git clone "$REPO_URL" "$PROJECT_NAME"
else
  npx create-payload-app@$PAYLOAD_VERSION "$PROJECT_NAME" --yes
fi

cd "$PROJECT_NAME"

# Step 6: Create .env file
cat <<EOF > .env
PAYLOAD_SECRET=$(openssl rand -hex 32)
MONGODB_URI=mongodb://localhost:27017/${PROJECT_NAME}
PORT=$APP_PORT
NODE_ENV=production
EOF

# Step 7: Install Node dependencies
npm install

# Step 8: Build the app
npm run build

# Step 9: Start with PM2
pm2 start dist/server.js --name payload
pm2 startup
pm2 save

# Step 10: UFW firewall
ufw allow OpenSSH
ufw allow "$APP_PORT"
ufw --force enable

# Step 11: Nginx reverse proxy
if [ "$USE_NGINX" = true ] && [ -n "$DOMAIN" ]; then
  echo -e "${GREEN}Setting up Nginx for $DOMAIN...${NC}"
  cat <<EOF > /etc/nginx/sites-available/payload
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

  ln -s /etc/nginx/sites-available/payload /etc/nginx/sites-enabled/
  nginx -t && systemctl restart nginx

  # Step 12: SSL with Certbot
  echo -e "${GREEN}Installing Certbot for HTTPS...${NC}"
  apt install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN
else
  echo -e "${GREEN}Skipping Nginx setup. App running on port $APP_PORT${NC}"
fi

# Final output
echo -e "${GREEN}Payload CMS deployed successfully!${NC}"
if [ -n "$DOMAIN" ]; then
  echo "→ Visit: https://$DOMAIN/admin"
else
  echo "→ Visit: http://your_server_ip:$APP_PORT/admin"
fi

