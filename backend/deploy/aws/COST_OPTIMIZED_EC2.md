# Cost-optimized EC2 backend setup

Goal: stop paying for an always-allocated Elastic IP while keeping the Android app usable from
`https://api.laltuguineapalace.com/api`.

## What changes

- The app uses `https://api.laltuguineapalace.com/api` instead of `http://13.235.125.127/api`.
- The wake Lambda starts EC2 and updates Hostinger DNS to the EC2 public IP for that boot.
- The backend can stop the EC2 instance after a short idle window, instead of waiting for fixed
  1 PM / 11 PM shutdowns.

## Hostinger DNS

Create a Hostinger API token from hPanel, then let Lambda manage this DNS record:

| Type | Name | Content | TTL |
| --- | --- | --- | --- |
| A | api | Updated by Lambda | 60 |

The Lambda uses:

```http
PUT https://developers.hostinger.com/api/dns/v1/zones/laltuguineapalace.com
```

with a zone body for the `api` A record.

## Lambda

Use Node.js 20.x or newer.

Files:

- `start-ec2-update-hostinger-dns.mjs`
- `package.json`

Environment variables:

```bash
EC2_INSTANCE_ID=i-xxxxxxxxxxxxxxxxx
HOSTINGER_API_TOKEN=your_hostinger_token
HOSTINGER_DOMAIN=laltuguineapalace.com
HOSTINGER_RECORD_NAME=api
HOSTINGER_TTL_SECONDS=60
```

IAM permissions for the Lambda role:

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

Set Lambda timeout to 2-3 minutes because EC2 may need time to boot.

The Lambda response includes:

```json
{
  "ok": true,
  "publicIp": "x.x.x.x",
  "apiUrl": "https://api.laltuguineapalace.com/api"
}
```

## EC2 and nginx

1. Update nginx with `backend/deploy/nginx-config.conf`.
2. Make sure port 80 and 443 are open in the EC2 security group.
3. After DNS points to the running EC2 public IP, run:

```bash
sudo certbot --nginx -d api.laltuguineapalace.com
```

Certificate renewal requires the instance to be running when certbot renews. If the instance is
usually stopped, schedule a monthly start window or use a DNS challenge flow.

## Backend idle auto-stop

Enable this only on EC2 production:

```bash
AUTO_STOP_AFTER_IDLE_MINUTES=25
AUTO_STOP_COMMAND=sudo /sbin/shutdown -h now
```

Before enabling, confirm the EC2 instance setting:

```bash
aws ec2 describe-instance-attribute \
  --instance-id i-xxxxxxxxxxxxxxxxx \
  --attribute instanceInitiatedShutdownBehavior
```

It must be `stop`, not `terminate`.

Allow the PM2/app user to run shutdown without a password. For example, if the app runs as `ubuntu`:

```bash
sudo visudo -f /etc/sudoers.d/laltu-api-shutdown
```

Add:

```text
ubuntu ALL=(root) NOPASSWD: /sbin/shutdown
```

If your server uses `/usr/sbin/shutdown`, update both the sudoers line and
`AUTO_STOP_COMMAND`.

## After testing

Once the domain-based flow works:

1. Remove the Elastic IP association.
2. Release the Elastic IP.
3. Keep EC2 auto-assign public IPv4 enabled for the subnet or network interface.

This shifts the public IPv4 charge from 24x7 to only the minutes/hours when EC2 is running.
