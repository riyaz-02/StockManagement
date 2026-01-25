# DigitalOcean Droplet Deployment Guide
# Laltu Guinea Palace Backend

## Prerequisites
- DigitalOcean account with $200 credit
- Domain name (api.laltuguineapalace.in)
- SSH key generated

---

## Step 1: Create DigitalOcean Droplet

### 1.1 Sign Up & Get Credits
1. Go to https://www.digitalocean.com/
2. Sign up with email
3. Verify email
4. Apply $200 credit (valid for 60 days)

### 1.2 Create Droplet
1. Click "Create" → "Droplets"
2. **Choose Region**: Bangalore (BLR1) or Mumbai
3. **Choose Image**: Ubuntu 22.04 LTS
4. **Choose Size**: Basic → $6/month (1GB RAM, 25GB SSD)
5. **Authentication**: 
   - Generate SSH key: `ssh-keygen -t rsa -b 4096`
   - Copy public key: `cat ~/.ssh/id_rsa.pub`
   - Add to DigitalOcean
6. **Hostname**: laltu-api-server
7. Click "Create Droplet"
8. **Note the IP address** (e.g., 143.110.xxx.xxx)

---

## Step 2: Initial Server Setup

### 2.1 Connect to Server
```bash
ssh root@YOUR_SERVER_IP
```

### 2.2 Run Setup Script
```bash
# Upload setup script
scp deploy/digitalocean-setup.sh root@YOUR_SERVER_IP:/root/

# Run it
ssh root@YOUR_SERVER_IP
chmod +x /root/digitalocean-setup.sh
./digitalocean-setup.sh
```

**OR manually run these commands:**

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js 18.x
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PM2
sudo npm install -g pm2

# Install Nginx
sudo apt install -y nginx

# Install Certbot
sudo apt install -y certbot python3-certbot-nginx

# Configure firewall
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

# Create app directory
sudo mkdir -p /var/www/laltu-api
sudo chown -R $USER:$USER /var/www/laltu-api
```

---

## Step 3: Deploy Application

### 3.1 Upload Backend Code

**Option A: Using Git (Recommended)**
```bash
cd /var/www/laltu-api
git clone https://github.com/YOUR_USERNAME/StockManagement.git .
cd backend
```

**Option B: Using SCP**
```bash
# From your local machine
cd f:\StockManagement\backend
scp -r * root@YOUR_SERVER_IP:/var/www/laltu-api/
```

### 3.2 Install Dependencies
```bash
cd /var/www/laltu-api
npm install --production
```

### 3.3 Create Environment File
```bash
nano .env
```

**Add this content:**
```env
NODE_ENV=production
PORT=5000

# Production MongoDB
MONGODB_URI=mongodb+srv://laltuguineapalaceonline:EmSKFbmZm51VAX57@clusterlgpadmin.ten2r.mongodb.net/jewellery_stock?retryWrites=true&w=majority&appName=ClusterLGPAdmin

# JWT
JWT_SECRET=dceb84e650b07523829dbc68dbb7e9aad0ea21f6fe550fa5759ef76a20601b789eafbcd1a2e783a1a85172
JWT_EXPIRE=7d

# File Upload
MAX_FILE_SIZE=5242880
UPLOAD_PATH=./uploads

# Cloudinary
CLOUDINARY_CLOUD_NAME=lgpstorage
CLOUDINARY_API_KEY=452155356611281
CLOUDINARY_API_SECRET=45h1ZJ7jl8yEkGEPm0CCtIjX_8Q

# CORS
CORS_ORIGIN=*

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
```

Save: `Ctrl+X`, `Y`, `Enter`

### 3.4 Test Application
```bash
node server.js
```

If it starts successfully, press `Ctrl+C` to stop.

### 3.5 Start with PM2
```bash
pm2 start server.js --name laltu-api
pm2 save
pm2 startup
```

Copy and run the command that PM2 outputs.

### 3.6 Verify Running
```bash
pm2 status
pm2 logs laltu-api
```

---

## Step 4: Configure Nginx

### 4.1 Create Nginx Configuration
```bash
sudo nano /etc/nginx/sites-available/laltu-api
```

**Paste this configuration:**
```nginx
server {
    listen 80;
    server_name api.laltuguineapalace.in;

    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    client_max_body_size 10M;

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss;
}
```

### 4.2 Enable Site
```bash
sudo ln -s /etc/nginx/sites-available/laltu-api /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

---

## Step 5: Configure Domain

### 5.1 Add DNS Record
In your domain registrar (e.g., GoDaddy, Namecheap):

1. Go to DNS settings for `laltuguineapalace.in`
2. Add A record:
   - **Type**: A
   - **Name**: api
   - **Value**: YOUR_SERVER_IP
   - **TTL**: 3600

Wait 5-10 minutes for DNS propagation.

### 5.2 Test Domain
```bash
curl http://api.laltuguineapalace.in
```

---

## Step 6: Setup SSL Certificate

### 6.1 Install SSL
```bash
sudo certbot --nginx -d api.laltuguineapalace.in
```

Follow prompts:
- Enter email
- Agree to terms
- Choose to redirect HTTP to HTTPS

### 6.2 Test SSL
```bash
curl https://api.laltuguineapalace.in
```

### 6.3 Auto-Renewal
Certbot auto-renews. Test it:
```bash
sudo certbot renew --dry-run
```

---

## Step 7: Update Flutter App

### 7.1 Update API Base URL
Edit `f:\StockManagement\flutter_app\lib\services\api_service.dart`:

```dart
class ApiService {
  // OLD: static const String baseUrl = 'https://your-railway-app.railway.app/api';
  static const String baseUrl = 'https://api.laltuguineapalace.in/api';
  
  // ... rest of code
}
```

### 7.2 Build New APK
```bash
cd f:\StockManagement\flutter_app
flutter build apk --release
```

### 7.3 Test
1. Install new APK on phone
2. Test login
3. Test all features
4. Verify fast response times!

---

## Step 8: Monitoring & Maintenance

### 8.1 Monitor Application
```bash
# View logs
pm2 logs laltu-api

# Monitor resources
pm2 monit

# Check status
pm2 status
```

### 8.2 Restart Application
```bash
pm2 restart laltu-api
```

### 8.3 Update Application
```bash
cd /var/www/laltu-api
git pull
npm install
pm2 restart laltu-api
```

### 8.4 Check Nginx Logs
```bash
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

---

## Troubleshooting

### Application won't start
```bash
pm2 logs laltu-api --lines 100
```

### Nginx errors
```bash
sudo nginx -t
sudo systemctl status nginx
```

### Firewall issues
```bash
sudo ufw status
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### MongoDB connection issues
```bash
# Test connection
node -e "require('mongoose').connect('YOUR_MONGODB_URI').then(() => console.log('Connected')).catch(e => console.error(e))"
```

---

## Performance Optimization

### Enable Nginx Caching
```bash
sudo nano /etc/nginx/nginx.conf
```

Add inside `http` block:
```nginx
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=api_cache:10m max_size=100m inactive=60m;
```

### PM2 Cluster Mode
```bash
pm2 start server.js --name laltu-api -i max
```

---

## Backup Strategy

### Daily Backup Script
```bash
#!/bin/bash
# /root/backup.sh

DATE=$(date +%Y%m%d)
BACKUP_DIR="/root/backups"

mkdir -p $BACKUP_DIR

# Backup application
tar -czf $BACKUP_DIR/laltu-api-$DATE.tar.gz /var/www/laltu-api

# Keep only last 7 days
find $BACKUP_DIR -name "laltu-api-*.tar.gz" -mtime +7 -delete
```

### Setup Cron
```bash
crontab -e
```

Add:
```
0 2 * * * /root/backup.sh
```

---

## Cost Summary

- **Droplet**: $6/month
- **Free credit**: $200 (33 months free!)
- **Domain**: Already owned
- **SSL**: Free (Let's Encrypt)

**Total**: $0 for first 33 months, then $6/month

---

## Success Checklist

- [ ] Server created and accessible
- [ ] Node.js and PM2 installed
- [ ] Application deployed and running
- [ ] Nginx configured
- [ ] Domain pointing to server
- [ ] SSL certificate installed
- [ ] Flutter app updated
- [ ] All features tested
- [ ] Response time < 500ms
- [ ] Monitoring setup

---

## Support Commands

```bash
# Server info
uname -a
free -h
df -h

# Application status
pm2 status
pm2 logs

# Nginx status
sudo systemctl status nginx
sudo nginx -t

# Firewall status
sudo ufw status

# SSL certificate info
sudo certbot certificates
```

---

## Next Steps After Deployment

1. Monitor performance for 24 hours
2. Test from multiple devices
3. Collect user feedback
4. Setup automated backups
5. Configure monitoring alerts
6. Document any custom configurations

---

**Your API will be live at**: `https://api.laltuguineapalace.in`

**Expected performance**: 200-400ms response time (10-30x faster than Railway!)
