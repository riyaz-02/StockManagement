#!/bin/bash
# DigitalOcean Droplet Setup Script for Laltu Guinea Palace Backend
# Run this script on a fresh Ubuntu 22.04 server

set -e  # Exit on error

echo "🚀 Starting DigitalOcean Droplet Setup..."

# Update system
echo "📦 Updating system packages..."
sudo apt update
sudo apt upgrade -y

# Install Node.js 18.x
echo "📦 Installing Node.js 18.x..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify Node.js installation
echo "✅ Node.js version:"
node --version
npm --version

# Install PM2 globally
echo "📦 Installing PM2 process manager..."
sudo npm install -g pm2

# Install Nginx
echo "📦 Installing Nginx..."
sudo apt install -y nginx

# Install Certbot for SSL
echo "📦 Installing Certbot..."
sudo apt install -y certbot python3-certbot-nginx

# Configure firewall
echo "🔒 Configuring firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

# Create application directory
echo "📁 Creating application directory..."
sudo mkdir -p /var/www/laltu-api
sudo chown -R $USER:$USER /var/www/laltu-api

# Install Git
echo "📦 Installing Git..."
sudo apt install -y git

echo "✅ Server setup complete!"
echo ""
echo "📝 Next steps:"
echo "1. Upload your backend code to /var/www/laltu-api"
echo "2. Run: cd /var/www/laltu-api && npm install"
echo "3. Create .env file with your environment variables"
echo "4. Start app with: pm2 start server.js --name laltu-api"
echo "5. Configure Nginx (see nginx-config.txt)"
echo "6. Setup SSL with: sudo certbot --nginx -d api.laltuguineapalace.in"
