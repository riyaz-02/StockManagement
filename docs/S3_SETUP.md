# Amazon S3 for uploads (photos, PDFs, videos)

From now on new files go to S3. Cloudinary keeps serving what it already holds (those links are stored in full in the database and keep working; deleting one still goes to Cloudinary). Until a bucket is set (`S3_BUCKET` in the server's `.env`) uploads keep going to Cloudinary, so nothing breaks while this is being set up.

## What gets stored where
`media/<what>/<yyyy>/<mm>/<random>.<ext>` in the bucket (`items`, `containers`, `users`, `purchase-bills`, `videos` ...). The random part makes a link impossible to guess. Photos are turned upright, shrunk to 1600 px (bills 2000 px), saved as **WebP** at quality 85 (measured on this shop's own photos: about 17 % smaller than the originals, and about 35 % smaller than the same photo as JPEG when it comes straight from a phone camera, at ~41 dB against the original = not visible; transparency is kept), the phone's GPS location is dropped, and a small copy (400 px, `<name>_t.webp`) is kept beside each. PDFs, videos and HEIC photos are stored as they are (videos stream in parts, up to 150 MB). What a file REALLY is, is read from its first bytes: a program renamed `.jpg` is refused.

API: `POST /api/upload/single | multiple | file`, `POST /api/upload/delete {url}` (see `docs/API.md`). The app's item / container / profile photos and the purchase bills use these. Deleting an item or a bill removes the file (and its small copy) from wherever it lives.

The updating of the server itself, step by step: `docs/EC2_DEPLOY.md`.

## One-time setup in the AWS console (about 15 minutes, region Asia Pacific (Mumbai) `ap-south-1`)

### 1. The bucket
S3 > **Create bucket**
- Name: for example `laltu-guinea-palace-media` (must be unique across AWS; add something if it is taken). Region: **ap-south-1**.
- Object Ownership: **ACLs disabled**.
- Block Public Access: **untick only "Block public access to buckets and objects granted through new public bucket or access point policies" and "...through any public bucket or access point policies"**, keep the two ACL ones ticked. Tick the warning box.
- Versioning off, default encryption on (SSE-S3). Create.

### 2. Let everyone READ the pictures (and nothing else)
Bucket > Permissions > **Bucket policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadMedia",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/media/*"
  }]
}
```
Only files under `media/` are readable, only by their exact (random) link; nobody can list or write. (Bills are as public as they were on Cloudinary: a link cannot be guessed. A later step can make `purchase-bills/` private with signed links.)

### 3. Tidy up broken uploads
Bucket > Management > **Create lifecycle rule** "abort-incomplete": apply to all objects, tick **Delete incomplete multipart uploads after 7 days**. (Costs nothing; stops a cut-off video upload from being kept and billed.)

### 4. Permission for the server: an IAM role on the EC2 instance (no keys anywhere)
IAM > Policies > **Create policy** > JSON, name `laltu-media-rw`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"], "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/media/*" },
    { "Effect": "Allow", "Action": ["s3:ListBucketMultipartUploads"], "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME" }
  ]
}
```
IAM > Roles > **Create role** > AWS service > **EC2** > attach `laltu-media-rw` > name `laltu-api-ec2-role`.
EC2 > Instances > the server (`stock-management-lgp`) > **Actions > Security > Modify IAM role** > choose `laltu-api-ec2-role` > Update. (Works while the instance is stopped.) The server then gets short-lived credentials by itself.

Do not create an IAM user with long-lived keys for this: the account's older keys (some over a year old) are better rotated or deleted too.

### 5. The server's settings
On EC2, in the backend `.env` add:
```
S3_BUCKET=YOUR-BUCKET-NAME
S3_REGION=ap-south-1
```
then `pm2 restart laltu-api --update-env` (or the normal `deploy-prod.ps1`, which installs the new packages: `@aws-sdk/client-s3`, `@aws-sdk/lib-storage`, `sharp`; the server must be x64 or arm64 Linux with Node 18.17+, which a standard Ubuntu EC2 is).

Raise nginx's upload limit (it is 10 MB now): in `/etc/nginx/sites-available/...` set `client_max_body_size 200M;` for the API, then `sudo nginx -t && sudo systemctl reload nginx`.

### 6. The website
Its pages may show pictures from `https://*.s3.ap-south-1.amazonaws.com` already. If you later put CloudFront in front, add its address to the website's `.env`: `PORTAL_IMG_HOSTS=https://files.example.com`.

## Check it works
In the app: add or edit an item with a photo; the stored link starts with `https://<bucket>.s3.ap-south-1.amazonaws.com/media/items/`. Open it in a browser. Delete the item: the file is gone. On the server, `pm2 logs laltu-api` shows `[upload]` lines only for refused files.

## Moving the old Cloudinary pictures later
Nothing needs doing now. When you want to: a one-off script copies each Cloudinary file into S3 and rewrites the item's link (ask for it; it should be rehearsed on a copy of the database, like the earlier merge). Until then both work side by side.

## Costs
About ₹1 to ₹30 a month at this shop's size (see the estimate in the chat history / `docs/CHANGELOG.md`): storage about ₹2 per GB-month, requests and transfer inside the free allowance.

## Tests
`node backend/scripts/media-store.test.js` runs the whole upload path against a tiny S3-compatible server built into the test (no AWS account needed): resizing, location removal, PDFs, videos in parts, refusals, deletion, no leftover temporary files.
