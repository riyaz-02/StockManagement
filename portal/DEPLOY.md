# Putting the website on Hostinger (do this only when you decide; nothing here has been run)

The website is PHP files only. It has no database. Every action goes to the same Node API the phone app uses.

## Before you start
1. **The API must be deployed with the new code first** (the website needs the new endpoints: live stream, calculate, audit...). On the EC2 server: pull the code, `npm install`, `pm2 restart laltu-api`. Check `https://api.laltuguineapalace.com/health` shows `"ready":true`.
2. Add these to the API's `.env` on the server, then restart it:
   - `PORTAL_SHARED_KEY=` a long random text (40+ characters). Same text goes into the website's `.env`. It lets the API count wrong passwords per visitor, not all staff together.
   - `CORS_ORIGIN=https://<your website address>` (only needed for the live-updates stream, which the browser opens straight to the API).
3. Secrets that were shown in screenshots earlier (Mongo password, Cloudinary secret, JWT secret) should be changed first. Changing `JWT_SECRET` signs everyone out once.

## On Hostinger
1. Make a subdomain, for example `app.laltuguineapalace.com`. PHP 8.2 or newer. Turn on the free SSL for it.
2. Upload the whole `portal/` folder (File Manager or FTP) **except** `.env`, `storage/*.log`, `tests/` (tests are optional). Point the subdomain's document root at `portal/public`.
3. In Hostinger's SSH or the "PHP Composer" tool, inside `portal/`: `composer install --no-dev --optimize-autoloader`.
4. Copy `.env.example` to `.env` (on the server) and set:
   ```
   PORTAL_ENV=prod
   PORTAL_API_BASE=https://api.laltuguineapalace.com
   PORTAL_WAKE_URL=<the wake function URL the app uses>
   PORTAL_SHARED_KEY=<the same long text as on the API>
   PORTAL_APP_NAME=Laltu Guinea Palace
   ```
   Leave `PORTAL_API_PUBLIC` empty unless the browser must use a different API address than the server does.
5. Make sure `storage/` can be written by PHP (folder permission 755 or 775 as Hostinger allows). It holds the sign-in brake files and (in `PORTAL_ENV=prod`) the compiled Twig page cache — both are created automatically the first time each is needed.
6. Open the website. First visit with the server asleep shows "Starting the server"; it wakes it and continues.

## Performance (already set up; nothing to do unless you change something)
- **Page cache**: `PORTAL_ENV=prod` compiles every page to plain PHP once (`storage/twig/`) instead of re-reading the template each visit. If a page ever looks stuck on old content after an upload, clear that folder.
- **PHP OPcache**: turn it on if Hostinger's panel offers it (most plans have it on by default) — it caches compiled PHP itself, on top of the Twig cache above. No code change needed either way.
- **Assets**: CSS/JS load with a version tag (`?v=<file time>`) and are told to cache for a year, gzip is on for text/CSS/JS/JSON (`public/.htaccess`) — a browser only re-downloads a file after it actually changes.
- **The rate limiter**: the API counts failed logins and general traffic per visitor address, using the `PORTAL_SHARED_KEY` forwarding from step 2. In production every real visitor already has their own address, so this needs no attention; it only needed a workaround (see `CLAUDE.md`) when running the test suite over and over from one developer machine.

## Check it works (5 minutes)
- Sign in with the admin mobile number. The green **Live** dot shows in the top bar.
- Change today's rate on the website: the app's rate strip changes at once (phone open, foreground).
- Publish a test app update from **Admin Control > App updates** with the same version as now (no harm): an open phone shows the update popup at once.
- Wrong password 6 times for one mobile number: the website makes that person wait 10 minutes; other staff can still sign in.

## Keeping it safe
- Never upload `.env`, never put the API password or database address in the website (it does not need them).
- Sessions sign out after `PORTAL_IDLE_MINUTES` (default 480 = 8 hours) of no use; the cookie is HttpOnly, Secure, SameSite=Lax.
- Every form carries a secret token (CSRF); every page has a strict Content-Security-Policy (only this site's scripts run).
- Updating the site later: upload changed files, run `composer install --no-dev` if `composer.lock` changed. Nothing else to migrate.

## Rolling back
Re-upload the previous folder. The API and the app are not affected by the website at all.
