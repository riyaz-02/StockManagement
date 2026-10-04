# CLAUDE.md — read this first (keep it short)

Jewellery stock + GST billing for a multi-branch shop. **Flutter Android app** (`flutter_app/`) + **Node/Express/Mongo REST API** (`backend/`). Live PHP website is `D:\LGPManagement` (not LGPAdmin); the app writes invoices into its `shopmanage.invoices` collection in the website's snake_case shape.

Deeper docs (open only what the task needs): `docs/ARCHITECTURE.md` · `docs/API.md` · `docs/DATA_MODEL.md` · `docs/BUSINESS_RULES.md` · `docs/DEV_TESTING.md` · `docs/WEB_SITE_PLAN.md` · `docs/WEB_PORTAL_PLAN.md` (the PHP portal plan: architecture, realtime, build order) · `docs/CHANGELOG.md`.

## Hard rules
- **Production DB is never altered/deleted.** Only guarded inserts/edits explicitly requested. Never run `deploy-prod.ps1`; never push/deploy/commit unless asked.
- Develop and test locally (dev DB, 127.0.0.1:27018). Keep dev/prod separate.
- Every feature is **branch-aware** (multi-shop). Stock models get it free from `utils/branchScope.js` (add `schema.plugin(branchPlugin)` to any new stock/ops model); never bypass Mongoose with raw collection reads for stock. GST is per **GSTIN** (`services/registrations.js`). Tablets get bigger fields, not more columns.
- Every new backend endpoint: `protect` + `requirePermission('x.y')` (admin/owner bypass) and add the key in `backend/config/permissions.js`.
- After any feature: update `docs/WEB_SITE_PLAN.md` (feature table), `docs/API.md` (if endpoints changed), `docs/CHANGELOG.md`.

## Commands
- Everything local: `.\dev-local.ps1` (DB + backend + adb reverse + app). Login mobile `7029621489` / `Admin@123`.
- DB only: `cd backend; node scripts/local-db.js`. Backend: `node server.js` (restart after edits).
- Tests: `cd backend; node scripts/db-backup.test.js (needs the local DB; throw-away DBs, dropped after); node scripts/user-model.test.js; node scripts/db-merge.test.js; node scripts/purchase-shared.test.js; node scripts/stock-present.test.js; node scripts/stock-summary.test.js; node scripts/stock-summary-api.test.js (server must run); node scripts/app-update.test.js (server must run; uses the built APK); node scripts/media-store.test.js; node scripts/media-api.test.js (starts its own server on :5055 against a fake S3); node scripts/gst-filings.test.js; node scripts/billing-calc.test.js; node scripts/gst-reports.test.js; node scripts/branch-scope.test.js; node scripts/api-smoke.js` (server must run). Flutter: `cd flutter_app; flutter test` (`widget_test.dart` is an old broken template: ignore).
- Realistic local data (18 months, 3 shops, purchases, filed returns): `node scripts/seed-sample-history.js` — re-run after `api-smoke.js` (which resets invoices). Branch logins `9000000011/12/13` / `Staff@123`.
- After changing `services/stockValuation.js`: `node scripts/gen-valuation-vectors.js`, keep `lib/utils/stock_valuation.dart` in sync (`node scripts/stock-valuation.test.js`, `flutter test test/stock_valuation_test.dart`).
- After changing `services/billingCalc.js`: `node scripts/gen-billing-vectors.js` (regenerates `flutter_app/test/billing_vectors.json`) and keep `lib/utils/billing_calc.dart` in sync; also `node scripts/gen-portal-calc.js` (browser copy of the engine for the website's New bill screen; `--check` is part of `portal/tests/billing.php`).

- Data backup (paste any MongoDB URI, download everything; Admin Control > Data backup in the portal): read-only, mongodump-format zip. Restore: `node backend/scripts/restore-backup.js <unzipped folder> <uri> [--apply]` (plan by default; only adds missing docs). Never point `--apply` at production unless asked.
- Web portal (PHP, `portal/`): `.\dev-portal.ps1` (needs the local API); tests `cd portal; php tests/all.php` (portal + dev API running; makes test records in the DEV db only). Deploy guide: `portal/DEPLOY.md` (never deploy unless told). It is a front end of the SAME Node API (never touches the DB, no rules duplicated). Plan: `docs/WEB_PORTAL_PLAN.md`.

## Where things live
- Stock Summary (metal balance / difference / snapshot / wastage): `backend/services/stockSummary.js` (pure engine) + `stockSummaryData.js` ↔ app `lib/screens/store_tabs/summary_tab.dart`, portal `/stock/summary`; spec `docs/STOCK_SUMMARY.md`.
- Uploads (photos / PDFs / videos): `backend/middleware/mediaUpload.js` + `services/mediaStore.js` (S3 when `S3_BUCKET` is set, else Cloudinary; deletes by link from either); setup `docs/S3_SETUP.md`.
- App updates + bell: `docs/APP_RELEASE.md` (build, upload on Admin > App updates, Publish), `backend/controllers/appVersionController.js` + `services/apkInfo.js`, `services/notificationFeed.js`; app `widgets/update_dialog.dart`, `widgets/notification_bell.dart`.
- Billing engine: `backend/services/billingCalc.js` ↔ `flutter_app/lib/utils/billing_calc.dart` (mirrors; shared vectors).
- Billing API: `controllers/billingController.js`, `services/billingView.js` (doc → view/row).
- GST reports: `services/gstReports.js` (pure), `controllers/gstReportsController.js`, `models/AppGst.js`, `services/gstReminderJob.js`.
- App screens: `lib/screens/` (billing: `create_invoice_screen`, `invoice_item_sheet`, `invoice_detail_screen`; GST: `gst_summary_screen` + `gst_*_view`/`gst_settings_screen`). API client: `lib/services/api_service.dart`. State: `lib/providers/`.

## One database
App and website share ONE database (the website's `shopmanage`; locally `lgp_dev`): `MONGODB_URI` is the only address (it must end with the db name) and `config/db.js` has ONE connection, `getConnection()`. Collections the website owns are never auto-created/indexed by the app; ONE collection per operation, in the website's shape (users, customers, invoices, purchases, gst_data = filed GST returns, outputDoc = generated GST records): the app adapts through the model/service (`models/User.js`, `models/Purchase.js` `toApp()`, `services/gstFilings.js`), never a second copy. Stock = items present + `bulk_weights` (no manual stock ledger; the website's own `stock_entries` is left alone). The web and the app are two ways to operate on the same data through the one API: every feature exists on both. The WEBSITE's structure is the master: `users` and `customers` are the website's collections (app adapts via `models/User.js` aliases, `services/customerStore.js`); app-only data lives in its own collections (`app_*`). Design, merge/cutover and open decisions: `docs/DB_UNIFICATION.md`. Merge tool `scripts/merge-app-into-website-db.js` is plan-by-default; never run it against production unless told.

## Gotchas
- Shell quoting breaks on apostrophes: write patch scripts with Write, run with python; keep apostrophes out of inline JS/Dart passed via bash.
- `pdf` package: use one-row `pw.Table` to keep a block unsplit; built-in font lacks "•" and ₹ (fallback "Rs."). NEVER reuse one widget instance in several places (a `pw.Table` keeps layout state: rows overlapped and a page vanished); never put `alignment:` on a Container inside a table cell (grows to the page's leftover height).
- Phone testing: `adb reverse tcp:5000 tcp:5000`; screen lag makes scripted taps miss → verify each step by screenshot.
- Local mongod dies between sessions → `node scripts/local-db.js`.
- Running the portal test suites (or `api-smoke.js`) many times in one session exhausts the API's per-IP rate limits (`.env` `RATE_LIMIT_MAX_REQUESTS=100`/15 min covers every unauthenticated call, i.e. every login the tests do) and logins start failing with 429/419 everywhere. Start the dev backend with both bumped: `$env:AUTH_LIMIT_MAX='2000'; $env:RATE_LIMIT_MAX_REQUESTS='20000'; node server.js` (a shell env var wins over `.env`).
- The future website is PHP on the same REST API (`docs/WEB_SITE_PLAN.md`): keep business rules on the server, never only in the app.
- htmx 2.x does NOT swap 4xx responses; the portal's `htmx-config` (base.twig) makes 422 swap so a form can show its inline error: keep returning 422 (not 400/409) for those. Pop-up forms that fail must be tested in the browser, the PHP tests only see status codes.
