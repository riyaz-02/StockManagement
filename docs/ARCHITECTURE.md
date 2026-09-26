# Architecture (short)

```
Flutter app (Provider) ──HTTPS JSON, Bearer JWT──▶ Express API ──▶ MongoDB
                                                       │
                                     ┌─────────────────┼──────────────────┐
                               primary DB         shopmanage DB       LGP admin cluster
                        jewellery_stock(_dev)   (website; invoices,   (getLgpAdminConnection;
                        items, containers,      shop_info numbering)   user directory/customers)
                        users, app_* collections
```
Locally all three DBs are on `127.0.0.1:27018` (fake data). Prod: EC2 + Lambda wake/DNS flow with auto-stop (see `AWS_COST_SAVING_README.md`).

## Backend (`backend/`)
`server.js` mounts routers under `/api/*` (list in `docs/API.md`). Layers: `routes/` → `controllers/` → `services/` (pure logic, unit-tested) + `models/` (Mongoose). Auth: `middleware/auth.js` (`protect`, `authorize(roles)`), permissions: `config/permissions.js` (`requirePermission`; roles Manager/Staff/Viewer + per-user overrides; admin/owner bypass). CORS from `CORS_ORIGIN` env. Scheduled jobs: `config/scheduledNotifications.js` (hourly GST reminders + boot catch-up, because EC2 sleeps).

## Flutter (`flutter_app/lib/`)
`main.dart` → providers (`auth_provider`, `store_provider`) → screens. All HTTP goes through `services/api_service.dart`. Pure Dart logic in `utils/` (billing_calc, gst_periods, invoice_pdf, gst_record_pdf) with tests in `test/`.

## Key design decisions
- **Pure engines shared JS↔Dart** with 400 generated vectors so app and server never disagree on money.
- **Idempotent writes**: `requestId` locks in `app_request_locks`; invoice numbers allocated atomically via `shop_info` (main shop: 4-digit continuing website sequence; branches `PREFIX-0001`).
- **App-owned collections are `app_*`**, beside legacy ones; legacy invoices are only read, new ones inserted in website shape.
