# AWS Cost Saving Setup Guide

This guide explains, step by step, how to reduce the monthly AWS bill for the
Laltu Guinea Palace app.

The main idea:

1. Use `api.laltuguineapalace.com` instead of the paid fixed Elastic IP.
2. Let Lambda start EC2 when the app opens.
3. Let Lambda update Hostinger DNS to the new EC2 public IP.
4. Let the backend stop EC2 automatically after the app is idle.
5. Release the Elastic IP only after everything is tested.

Do not release the Elastic IP first. Do that only near the end of this guide.

---

## Why you are paying money now

Your app was using this fixed IP:

```text
http://13.235.125.127/api
```

That IP is most likely an Elastic IP or always-allocated public IPv4 address.
AWS charges for public IPv4 addresses by the hour, even when EC2 is stopped.

That is why the EC2 compute cost is low, but the VPC cost is still around
`$3.60-$3.72` every month.

Your target setup should be:

```text
https://api.laltuguineapalace.com/api
```

Then the EC2 can use a temporary public IP only while it is running.

---

## What has already been changed in the project

These project files are already prepared:

```text
flutter_app/lib/utils/app_constants.dart
```

Production API is now:

```text
https://api.laltuguineapalace.com/api
```

Nginx config is now prepared for:

```text
api.laltuguineapalace.com
```

New AWS Lambda helper files were added here:

```text
backend/deploy/aws/
```

The backend also has optional auto-stop support:

```text
backend/config/idleShutdown.js
```

---

## Step 1: Hostinger - create the API subdomain

First create the subdomain/DNS record while the old Elastic IP is still active.

1. Open Hostinger hPanel.
2. Go to your domain:

```text
laltuguineapalace.com
```

3. Open DNS Zone / DNS Records.
4. Create or edit this record:

```text
Type: A
Name: api
Points to: 13.235.125.127
TTL: 60 seconds if available, otherwise use the lowest value Hostinger allows
```

5. Save it.

This creates:

```text
api.laltuguineapalace.com
```

6. Wait a few minutes.
7. Test in browser:

```text
http://api.laltuguineapalace.com/health
```

Expected result:

```json
{
  "status": "ok"
}
```

If this does not work, do not continue yet.

---

## Step 2: EC2 - update nginx to use the new domain

SSH into the EC2 server.

Go to your backend deployment folder. It may be something like:

```bash
cd /var/www/laltu-api
```

Copy or update nginx using this project file:

```text
backend/deploy/nginx-config.conf
```

The important line should be:

```nginx
server_name api.laltuguineapalace.com;
```

Then test and reload nginx:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

---

## Step 3: EC2 Security Group - allow web traffic

In AWS Console:

1. Go to EC2.
2. Open Instances.
3. Select your backend instance.
4. Open the Security tab.
5. Click the Security Group.
6. Check Inbound Rules.

You need these rules:

```text
HTTP   TCP 80   Source 0.0.0.0/0
HTTPS  TCP 443  Source 0.0.0.0/0
Custom TCP 5000 should NOT be open publicly if nginx is proxying correctly
```

Port `5000` can remain private/local because nginx forwards traffic to it on the
same machine.

---

## Step 4: EC2 - add SSL certificate

Only do this after `http://api.laltuguineapalace.com/health` works.

On the EC2 server:

```bash
sudo certbot --nginx -d api.laltuguineapalace.com
```

After that, test:

```text
https://api.laltuguineapalace.com/health
```

Expected result:

```json
{
  "status": "ok"
}
```

If HTTPS does not work, do not release the Elastic IP yet.

---

## Step 5: AWS Lambda - update DNS automatically after EC2 starts

This is the most important part.

When the Elastic IP is removed, EC2 will get a different public IP after start.
So Lambda must update Hostinger DNS every time it starts EC2.

### 5.1 Create Hostinger API token

In Hostinger:

1. Open hPanel.
2. Go to Account / API / API tokens.
3. Create a new API token.
4. Copy the token.

Keep this token private.

### 5.2 Update your existing Lambda

In AWS Console:

1. Go to Lambda.
2. Open your existing EC2 start Lambda.
3. Keep the same Function URL if possible, because the app already uses it.
4. Runtime should be Node.js 20.x or newer.
5. Handler should be:

```text
start-ec2-update-hostinger-dns.handler
```

6. Upload/deploy the code from:

```text
backend/deploy/aws/
```

That folder contains:

```text
start-ec2-update-hostinger-dns.mjs
package.json
```

### 5.2.1 Create the Lambda zip from Windows

On your computer, open PowerShell:

```powershell
cd F:\StockManagement\backend\deploy\aws
npm install --omit=dev
Compress-Archive -Path .\start-ec2-update-hostinger-dns.mjs, .\package.json, .\node_modules -DestinationPath .\laltu-ec2-wake-lambda.zip -Force
```

Then in AWS Lambda:

1. Open the Lambda function.
2. Go to Code.
3. Click Upload from.
4. Choose `.zip file`.
5. Upload:

```text
F:\StockManagement\backend\deploy\aws\laltu-ec2-wake-lambda.zip
```

6. Click Deploy if AWS shows a Deploy button.

### 5.3 Lambda environment variables

In the Lambda Configuration tab, add:

```text
EC2_INSTANCE_ID=i-xxxxxxxxxxxxxxxxx
HOSTINGER_API_TOKEN=your_hostinger_api_token
HOSTINGER_DOMAIN=laltuguineapalace.com
HOSTINGER_RECORD_NAME=api
HOSTINGER_TTL_SECONDS=60
```

Replace `i-xxxxxxxxxxxxxxxxx` with your actual EC2 instance ID.

### 5.4 Lambda timeout

Set Lambda timeout to:

```text
3 minutes
```

EC2 may need time to boot.

### 5.5 Lambda permissions

The Lambda execution role needs permission to start and describe EC2 instances.

Add this IAM policy to the Lambda role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:StartInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

### 5.6 Lambda Function URL

In Lambda:

1. Open Configuration.
2. Open Function URL.
3. Keep or create a Function URL.
4. Auth type can be `NONE` if your app calls it directly.
5. Enable CORS if available.
6. Allow methods:

```text
GET
POST
OPTIONS
```

7. Allow origin:

```text
*
```

Important: a public Function URL can be called by anyone who knows it. For now,
keep the URL private. Later, we can add a secret token to the app and Lambda.

---

## Step 6: Test before releasing Elastic IP

Do this while the Elastic IP still exists.

1. Stop the EC2 instance manually from AWS Console.
2. Open the Android app.
3. Press the Start button.
4. Wait for the server to start.
5. Check this URL:

```text
https://api.laltuguineapalace.com/health
```

Expected:

```json
{
  "status": "ok"
}
```

6. Check Hostinger DNS record.

The `api` A record should point to the current EC2 public IP.

If this works, the domain/Lambda/DNS flow is working.

---

## Step 7: Enable backend auto-stop after daily use

This reduces cost when the app is opened every day for only 10-15 minutes.

Without this, EC2 may keep running until your old fixed stop times: 1 PM and
11 PM. That can waste many hours.

### 7.1 Confirm shutdown behavior

In AWS Console:

1. Go to EC2.
2. Select the instance.
3. Open Actions.
4. Open Instance settings.
5. Find shutdown behavior / instance initiated shutdown behavior.
6. It must be:

```text
Stop
```

Not:

```text
Terminate
```

This is very important.

### 7.2 Add backend environment variables

On the EC2 backend `.env` file, add:

```bash
AUTO_STOP_AFTER_IDLE_MINUTES=25
AUTO_STOP_COMMAND=sudo /sbin/shutdown -h now
```

Recommended value:

```text
25 minutes
```

So if the shop uses the app for 10-15 minutes, EC2 should stop around 25 minutes
after the last real API request.

### 7.3 Allow backend user to run shutdown

If the backend runs as user `ubuntu`, run:

```bash
sudo visudo -f /etc/sudoers.d/laltu-api-shutdown
```

Add this line:

```text
ubuntu ALL=(root) NOPASSWD: /sbin/shutdown
```

If your server uses `/usr/sbin/shutdown`, use that path instead.

Check path:

```bash
which shutdown
```

### 7.4 Restart backend

If you use PM2:

```bash
pm2 restart laltu-api --update-env
```

Now EC2 should stop automatically after being idle.

Keep your old 1 PM and 11 PM shutdown rules for now as backup.

---

## Step 8: Only now release the Elastic IP

Do this only after all tests above work.

In AWS Console:

1. Go to EC2.
2. In the left menu, open Elastic IPs.
3. Select:

```text
13.235.125.127
```

4. Click Actions.
5. Click Disassociate Elastic IP address.
6. Confirm.
7. Select the same Elastic IP again.
8. Click Actions.
9. Click Release Elastic IP address.
10. Confirm.

After release, AWS should stop charging the always-on Elastic IP/public IPv4
cost.

Important: do not release it until the domain setup is tested.

---

## Step 9: Final test after releasing Elastic IP

1. Stop EC2.
2. Wait 1-2 minutes.
3. Open the app.
4. Press Start.
5. Wait until app reaches login/home.
6. Open:

```text
https://api.laltuguineapalace.com/health
```

Expected:

```json
{
  "status": "ok"
}
```

7. Check EC2 public IPv4 in AWS Console.
8. Check Hostinger `api` A record.

Both should match.

---

## If something breaks

### App does not connect

Check:

```text
https://api.laltuguineapalace.com/health
```

If it does not work:

1. Check EC2 is running.
2. Check EC2 has a public IPv4 address.
3. Check Hostinger `api` A record points to that public IP.
4. Check nginx is running.
5. Check backend is running.

### EC2 starts but has no public IP

This can happen depending on how the instance/network was created.

Temporary rollback:

1. Allocate a new Elastic IP.
2. Associate it with the EC2 instance.
3. Point Hostinger `api` record to the new Elastic IP.

Permanent fix:

Create a replacement EC2 instance or launch template in a subnet that auto-assigns
public IPv4 addresses, then move the backend there.

### Auto-stop does not work

Check:

1. `AUTO_STOP_AFTER_IDLE_MINUTES` is set.
2. `AUTO_STOP_COMMAND` is set.
3. The backend was restarted with updated env.
4. The backend user has passwordless sudo permission for shutdown.
5. EC2 shutdown behavior is `Stop`, not `Terminate`.

---

## Expected cost after this setup

Your current monthly cost is around:

```text
$5.32/month
```

After releasing the Elastic IP and using auto-stop:

```text
Public IPv4: only while EC2 is running
EC2 compute: only while EC2 is running
EBS disk: still charged monthly
Tax: still applies
```

If the app is used daily for around 10-15 minutes, and EC2 stops after 25 idle
minutes, the server may run roughly 40 minutes per day instead of many hours.

The biggest saving should come from removing the always-on Elastic IP charge.

---

## Simple checklist

Use this as your progress checklist:

```text
[ ] Hostinger api A record created
[ ] http://api.laltuguineapalace.com/health works
[ ] nginx updated to api.laltuguineapalace.com
[ ] HTTPS certificate installed
[ ] https://api.laltuguineapalace.com/health works
[ ] Lambda updated with Hostinger DNS updater
[ ] Lambda env variables added
[ ] Lambda IAM permissions added
[ ] App start button starts EC2 successfully
[ ] Hostinger api A record updates automatically
[ ] Backend idle auto-stop enabled
[ ] EC2 shutdown behavior confirmed as Stop
[ ] Elastic IP disassociated
[ ] Elastic IP released
[ ] Final app test passed
```

Do the Elastic IP release only after every earlier item is complete.
