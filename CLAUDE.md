# CLAUDE.md — read this first (keep it short)

Jewellery stock + GST billing for a multi-branch shop. **Flutter Android app** (`flutter_app/`) + **Node/Express/Mongo REST API** (`backend/`). Live PHP website is `D:\LGPManagement` (not LGPAdmin); the app writes invoices into its `shopmanage.invoices` collection in the website's snake_case shape.

Deeper docs (open only what the task needs): `docs/ARCHITECTURE.md` · `docs/API.md` · `docs/DATA_MODEL.md` · `docs/BUSINESS_RULES.md` · `docs/DEV_TESTING.md` · `docs/WEB_SITE_PLAN.md` · `docs/CHANGELOG.md`.

## Hard rules
- **Production DB is never altered/deleted.** Only guarded inserts/edits explicitly requested. Never run `deploy-prod.ps1`; never push/deploy/commit unless asked.
- Develop and test locally (dev DB, 127.0.0.1:27018). Keep dev/prod separate.
- Every feature is **branch-aware** (multi-shop). Stock models get it free from `utils/branchScope.js` (add `schema.plugin(branchPlugin)` to any new stock/ops model); never bypass Mongoose with raw collection reads for stock. GST is per **GSTIN** (`services/registrations.js`). Tablets get bigger fields, not more columns.
- Every new backend endpoint: `protect` + `requirePermission('x.y')` (admin/owner bypass) and add the key in `backend/config/permissions.js`.
- After any feature: update `docs/WEB_SITE_PLAN.md` (feature table), `docs/API.md` (if endpoints changed), `docs/CHANGELOG.md`.

## Commands
- Everything local: `.\dev-local.ps1` (DB + backend + adb reverse + app). Login mobile `7029621489` / `Admin@123`.
- DB only: `cd backend; node scripts/local-db.js`. Backend: `node server.js` (restart after edits).
- Tests: `cd backend; node scripts/billing-calc.test.js; node scripts/gst-reports.test.js; node scripts/branch-scope.test.js; node scripts/api-smoke.js` (server must run). Flutter: `cd flutter_app; flutter test` (`widget_test.dart` is an old broken template: ignore).
- Realistic local data (18 months, 3 shops, purchases, filed returns): `node scripts/seed-sample-history.js` — re-run after `api-smoke.js` (which resets invoices). Branch logins `9000000011/12/13` / `Staff@123`.
- After changing `services/stockValuation.js`: `node scripts/gen-valuation-vectors.js`, keep `lib/utils/stock_valuation.dart` in sync (`node scripts/stock-valuation.test.js`, `flutter test test/stock_valuation_test.dart`).
- After changing `services/billingCalc.js`: `node scripts/gen-billing-vectors.js` (regenerates `flutter_app/test/billing_vectors.json`) and keep `lib/utils/billing_calc.dart` in sync.

## Where things live
- Billing engine: `backend/services/billingCalc.js` ↔ `flutter_app/lib/utils/billing_calc.dart` (mirrors; shared vectors).
- Billing API: `controllers/billingController.js`, `services/billingView.js` (doc → view/row).
- GST reports: `services/gstReports.js` (pure), `controllers/gstReportsController.js`, `models/AppGst.js`, `services/gstReminderJob.js`.
- App screens: `lib/screens/` (billing: `create_invoice_screen`, `invoice_item_sheet`, `invoice_detail_screen`; GST: `gst_summary_screen` + `gst_*_view`/`gst_settings_screen`). API client: `lib/services/api_service.dart`. State: `lib/providers/`.

## Gotchas
- Shell quoting breaks on apostrophes: write patch scripts with Write, run with python; keep apostrophes out of inline JS/Dart passed via bash.
- `pdf` package: use one-row `pw.Table` to keep a block unsplit; built-in font lacks "•" and ₹ (fallback "Rs."). NEVER reuse one widget instance in several places (a `pw.Table` keeps layout state: rows overlapped and a page vanished); never put `alignment:` on a Container inside a table cell (grows to the page's leftover height).
- Phone testing: `adb reverse tcp:5000 tcp:5000`; screen lag makes scripted taps miss → verify each step by screenshot.
- Local mongod dies between sessions → `node scripts/local-db.js`.
- The future website is PHP on the same REST API (`docs/WEB_SITE_PLAN.md`): keep business rules on the server, never only in the app.
