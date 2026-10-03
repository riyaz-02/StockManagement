# Laltu Guinea Palace: web portal (PHP)

The website on top of the app. It is a **front end only**: every action goes to the same Node API the phone app uses
(`backend/`), so prices, GST, discounts, permissions and branch rules are decided in ONE place. It never touches the
database. See `docs/WEB_PORTAL_PLAN.md` for the plan.

## Run it locally (dev database only)
```
cd backend;  node scripts/local-db.js        # local Mongo on 127.0.0.1:27018 (if not running)
cd backend;  node server.js                  # API on :5000
cd portal;   composer install                # first time
cd portal;   php -S localhost:8080 -t public router.php
```
Open http://localhost:8080 . Dev logins: see CLAUDE.md (admin `7029621489`, branch staff `9000000011`).
Or run `.\dev-portal.ps1` from the repo root.

## Settings (`portal/.env`, never committed; copy `.env.example`)
`PORTAL_ENV` (dev|prod), `PORTAL_API_BASE` (API address), `PORTAL_WAKE_URL` (the start-up function that wakes the server),
`PORTAL_IDLE_MINUTES`. A real environment variable overrides the file.

## Tests
```
php tests/run.php                       # helpers (no server needed)
php tests/smoke.php [http://localhost:8080]   # end to end: needs the portal and the dev API running
php tests/pages.php                     # Day Book, Expenses, Dues, Orders, Old Metal
php tests/billing.php                   # GST Billing and Estimates (makes test bills in the DEV database)
php tests/stock.php | purchases.php | tally.php | directory.php | gst.php | admin.php   # one suite per area
php tests/all.php                       # every suite in turn
```

## Pages built
Home (rate strip, today's money) · GST Billing (list, bill, print, new bill, returns) · Estimates · Orders · Pending dues · Stock · Old Metal · Purchases · Stock Tally · Day Book · Expenses · Customers & suppliers.
GST Summary · Reports · Admin Control (Staff & roles, App updates, Notifications, App settings, Audit log, Server status).

## Folders
`src/` code (Api client, Auth session/CSRF/brake, Http controllers + middleware, Support helpers) ·
`templates/` Twig pages · `lang/` words (English first; add `bn.php` for Bengali) ·
`public/` the only folder the web server exposes (index.php, assets) · `storage/` small runtime files.

## Deploying to Hostinger (later, when told)
Upload the folder, point the site (or subdomain) to `public/`, run `composer install --no-dev`, create `.env` with
`PORTAL_ENV=prod`, `PORTAL_API_BASE=https://api.laltuguineapalace.com`, `PORTAL_WAKE_URL=<the wake function URL>`.
Nothing here needs a database on the hosting.
