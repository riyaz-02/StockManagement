# Architecture (short)

```
Flutter app (Provider) ──HTTPS JSON, Bearer JWT──▶ Express API ──▶ MongoDB: ONE database (the website's `shopmanage`)
Web portal (PHP) ───────HTTPS JSON, Bearer JWT──▶      │
Legacy PHP website (D:\LGPManagement) ───── reads/writes the SAME database directly
```
One database holds everything: the website's own collections (`customers`, `users`, `invoices`, `shop_info` ...) with the app's collections (`items`, `containers`, `app_*` ...) added next to them, so the phone app, the portal and the website work on the same records. The website's structure is the master; the app adapts to it. Full rules, the collection ownership table and the merge procedure: `docs/DB_UNIFICATION.md`. `MONGODB_URI` is the only database address; locally it is `127.0.0.1:27018/lgp_dev` (fake data). Prod: EC2 + Lambda wake/DNS flow with auto-stop (see `AWS_COST_SAVING_README.md`).

## Backend (`backend/`)
`server.js` mounts routers under `/api/*` (list in `docs/API.md`). Layers: `routes/` → `controllers/` → `services/` (pure logic, unit-tested) + `models/` (Mongoose). Auth: `middleware/auth.js` (`protect`, `authorize(roles)`), permissions: `config/permissions.js` (`requirePermission`; roles Manager/Staff/Viewer + per-user overrides; admin/owner bypass). CORS from `CORS_ORIGIN` env. Scheduled jobs: `config/scheduledNotifications.js` (hourly GST reminders + boot catch-up, because EC2 sleeps).

## Flutter (`flutter_app/lib/`)
`main.dart` → providers (`auth_provider`, `store_provider`) → screens. All HTTP goes through `services/api_service.dart`. Pure Dart logic in `utils/` (billing_calc, gst_periods, invoice_pdf, gst_record_pdf) with tests in `test/`.

## Key design decisions
- **Pure engines shared JS↔Dart** with 400 generated vectors so app and server never disagree on money.
- **Idempotent writes**: `requestId` locks in `app_request_locks`; invoice numbers allocated atomically via `shop_info` (main shop: 4-digit continuing website sequence; branches `PREFIX-0001`).
- **App-owned collections are `app_*`**, beside legacy ones; legacy invoices are only read, new ones inserted in website shape.
