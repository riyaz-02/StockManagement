# Dev & testing workflow

1. `.\dev-local.ps1` (or `node scripts/local-db.js` + `node server.js` in `backend/`). `backend/.env` points at local DB; prod URIs are commented (backup `.env.prod-backup`). Restart server after backend edits.
2. Backend checks (fast → slow):
   - `node scripts/billing-calc.test.js` (29 tests incl. 3000-case fuzz)
   - `node scripts/gst-reports.test.js` (28)
   - `node scripts/branch-scope.test.js` (7; branch isolation of stock models, local DB only)
   - `node scripts/api-smoke.js` (~328 end-to-end checks incl. multi-branch; reseeds legacy invoices via `seed-legacy-invoices.js`, cleans its test data). **It wipes local invoices: afterwards run `node scripts/seed-sample-history.js`** to get the realistic 18-month data back.
   - `node scripts/check-invoice-compat.js` — read-only check against prod shape.
3. Flutter: `flutter test` (billing vectors, gst_periods, gst_record_pdf), `flutter analyze`.
4. Engine change → `node scripts/gen-billing-vectors.js`, update Dart mirror, run both test suites.
5. Phone: `adb devices`, `adb reverse tcp:5000 tcp:5000`, `adb exec-out screencap -p`. Verify each tap by screenshot.
6. Production: never deploy without being asked; `deploy-prod.ps1` is not to be run by Claude.

Token-saving tips for Claude: read `CLAUDE.md` + only the one doc needed; grep before reading big screens (`create_invoice_screen.dart`, `gst_summary_screen.dart` are large); use scratchpad python patch scripts for multi-file edits.
