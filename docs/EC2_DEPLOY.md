# Updating the backend on EC2 (step by step)

You run these yourself; nothing here has been run by Claude. The release that is waiting contains EVERYTHING built since the database merge (one database, billing rules, Summary, app updates by upload, the bell, S3 uploads). Because the new server needs ONE database address, **the `.env` change and the code deploy go together**: this is the "cutover" of `docs/DB_UNIFICATION.md`.

## Before you start (on your computer)
1. **Tell the shop** a short pause is coming. Pick a quiet time (late evening).
2. **Backups exist**: the production backup of 3 Oct (`E:\lgp-backup-clusterlgpadmin-...zip`). Take a fresh one right before the cutover: website > Admin Control > Data backup (paste the production address, Download). Keep the zip.
3. **Commit and push** what you want to ship (the deploy script pushes commits only; it does NOT ship uncommitted files):
   ```powershell
   cd F:\StockManagement
   git status                 # read the list: no .env, no key files (they are ignored)
   git add -A
   git commit -m "One database, billing v3, stock summary, app updates, bell, S3 uploads"
   ```
   (Do not push yet: `deploy-prod.ps1` asks and pushes.)

## On the server (EC2) - connect
4. Wake and connect. The deploy script wakes the server by itself; for a manual look, open the wake link once in a browser, wait ~2 minutes, then:
   ```powershell
   ssh -i "<path to your .pem key>" ubuntu@api.laltuguineapalace.com
   ```
5. Look around (read only):
   ```bash
   node -v                      # must be v18.17 or newer (v20 is better)
   pm2 status                   # the process 'laltu-api' should be online
   cd /home/ubuntu/StockManagement/backend && ls  # the git clone (if your folder differs, fix $RemoteRepo in deploy-prod.ps1)
   grep -o '^[A-Z_0-9]*=' .env  # the NAMES of the settings (not the values)
   ```
   If `node -v` is older than 18.17, stop and tell me (Node must be upgraded first).

## The `.env` on the server
6. Keep a copy, then edit:
   ```bash
   cp .env .env.backup-before-cutover
   nano .env
   ```
   Make these changes (Ctrl+O, Enter, Ctrl+X to save):
   - `MONGODB_URI=` the production address of the **website's database**: it must **end with `/shopmanage`** (before any `?options`). It is the same address you keep in your Windows variable `LGP_PROD_URI`: copy it from there; never paste it into a chat or a file in the project.
   - **Delete** the lines `SHOPMANAGE_DB_URI=` and `LGP_ADMIN_DB_URI=` if they exist (the new server uses only `MONGODB_URI`).
   - **Add**:
     ```
     S3_BUCKET=laltu-guinea-palace-media
     S3_REGION=ap-south-1
     ```
   - **Keep** `JWT_SECRET`, the `CLOUDINARY_*` lines, `CORS_ORIGIN`, `PORT` and the auto-stop lines as they are.
7. Check the instance role reaches S3 (the role from `docs/S3_SETUP.md` step 4):
   ```bash
   TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
   curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/
   ```
   It should print the role name (`laltu-api-ec2-role`). If it prints nothing, the role is not attached to the instance (EC2 > the server > Actions > Security > Modify IAM role).

## nginx (so big files can come in)
8. Find and raise the upload limit (it is 10 MB; an app update is ~45 MB, videos more):
   ```bash
   grep -rn client_max_body_size /etc/nginx/
   sudo nano <the file that line is in>      # change 10M to 200M
   sudo nginx -t                              # must say "syntax is ok"
   sudo systemctl reload nginx
   ```

## The cutover (in this order)
9. **Sign-in gate ON** (website > Admin Control > App updates > Sign-in gate, "Stop new sign-ins now"; Admin/Owner can still sign in).
10. **Catch up the data written since the merge** (the old server still writes to the old app database until now). From your computer, plan first, then apply (the tool never writes to the source and only adds missing documents; details in `docs/DB_UNIFICATION.md`): ask Claude to run the plan against production read-only and show it to you before `--apply`.
11. **Deploy**:
    ```powershell
    cd F:\StockManagement
    .\deploy-prod.ps1
    ```
    It asks twice (push? connect?). It pushes, wakes the server, pulls, runs `npm install --omit=dev` (this installs the new packages `sharp`, `@aws-sdk/*`; it can take a few minutes on a small server), restarts `laltu-api`, and checks `/health`.
12. **Look at the logs** on the server for anything red:
    ```bash
    pm2 logs laltu-api --lines 60 --nostream
    ```
    You should see the database connect to `shopmanage` and no "S3" or "sharp" errors. If `sharp` failed to install: `cd /home/ubuntu/StockManagement/backend && npm install --omit=dev` and read the error.
13. **Test**, signed in as admin on the website and the app: Home, a bill, the Summary; add an item with a photo: its link must start with `https://laltu-guinea-palace-media.s3.ap-south-1.amazonaws.com/media/items/` and open in a browser; delete the test item.
14. **Sign-in gate OFF.**

## If something goes wrong
- The server will not start: `pm2 logs laltu-api`. Most likely `MONGODB_URI` (must end with the database name) or a missing package.
- Go back: `cd /home/ubuntu/StockManagement/backend && git log --oneline -3` (note the older commit), `git checkout <older commit>`, `cp .env.backup-before-cutover .env`, `npm install --omit=dev`, `pm2 restart laltu-api --update-env`. (Within the first day this works; after that new data exists only in `shopmanage`.)
- Photos do not upload: `S3_BUCKET` typo, the role not attached (step 7), or the bucket policy; `pm2 logs` shows the AWS message. With no `S3_BUCKET` set, uploads go to Cloudinary as before.
