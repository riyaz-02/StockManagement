# Web Portal plan (PHP) - Laltu Guinea Palace

Status: Phase 0 DONE (foundation, login, wake screen, Home). Phase 1 DONE (realtime spine). Phase 2a DONE (Day Book, Expenses, Dues, Orders, Old Metal). Phase 2b DONE (GST Billing list/bill/print/new bill/returns, Estimates). Phase 2c DONE (Stock, Purchases, Stock Tally, Customers & suppliers). Phase 3 DONE (GST Summary, Reports). Phase 4 DONE (Admin Control: staff & roles, app updates, notifications, app settings, audit log, server status). Phase 5 DONE (security review, shared-address login limiter fix, portal/DEPLOY.md). ALL PHASES BUILT. Since then: a UI pass to align every page with the app (module-coloured icons throughout, the New bill screen rebuilt to match the app's billing screen), a CSS cleanup/hardening pass, a "solid/professional" restyle (flatter badges, bordered cards, no glow), fuller list columns + fewer clicks on Estimates/Purchases/Dues/GST bills/Orders/Stock/Stock Tally, an htmx modal-target bug fix (checked every modal for the same class of bug), and the audit log widened to cover every real business action (bills, returns, stock, purchases, old metal, orders, estimates, expenses, GST filings, tallies) from BOTH the app and the website in one place, with colour-coded actions and a compact-row-plus-details-modal layout. Then: the App updates page fixed (a real `.kv-row` wrapping bug) and widened with a sign-in gate (blocks new logins app+website, admin/owner exempt) and a recent-publishes history (free, from the audit log); and live staff presence ("who's live, on what page", app + website) added — an in-memory `/api/presence` registry, a heartbeat from both `app.js` and a new `lib/services/presence_service.dart`, and a "Live now" panel on Staff & Roles. The Flutter changes (presence pings + named routes on the 15 module screens) could not be run in this environment (no device/emulator) — `dart analyze` is clean but a real build should confirm before relying on it. Then: Admin Control > Data backup (paste a MongoDB address, download every record in mongodump format + a restore script; read-only) and two long-standing portal bugs fixed (validation errors in pop-ups never showed; flash messages after a redirect only showed on Home). Then: the app and website databases were unified in design and code (one `shopmanage`, website structure is master, users and customers common; `docs/DB_UNIFICATION.md`), and the portal sign-in now also takes a username or e-mail, with Username / E-mail on Staff & Roles. Awaiting the owner's review. Not deployed. Working autonomously through the phases; dev database (127.0.0.1:27018) only.

## REVISION 2 (final decisions) - supersedes sections 2, 5, 8 and any "API / direct Atlas" idea
- **Hosting: Hostinger** for the PHP portal only (cheap, always on).
- **ONE backend serves both the app and the website.** The portal never touches the database; it is a pure client of the Node API, exactly like the app. Every rule, permission, branch filter and notification is written once, in Node, and reused.
- **The backend starts when EITHER the app OR the website is used, and stops when NEITHER is used** (as today). Later, when you want it on during working hours, only a schedule is added (see "Later").
- **Same role-based login, same users, same DB** (the API's login and permission system, unchanged). English first, Bengali gradually.

### Architecture
```
 Browser --> Hostinger PHP portal --HTTPS--> Node API on EC2 --> MongoDB Atlas   <-- Phone app (same API)
                 |                                ^
                 +-- wakes EC2 (same Lambda as the app) when it is asleep
```
- PHP is a thin BFF: renders pages, keeps the API token in the PHP session (never in browser JavaScript), forwards actions to `/api/...`. No MongoDB extension, no Atlas IP allow-list, no shared JWT secret, no duplicated permission code on Hostinger.
- **Start-up flow (same as the app):** open the portal -> it checks `/health` (ready = databases connected) -> if asleep it calls the wake Lambda and shows a friendly "Starting the server... about 1-2 minutes" screen with progress -> then the login page. While waiting, the portal page itself is served from Hostinger instantly.
- **Stopping:** the existing idle-stop counts real API requests from the app and the portal. Rules so the portal does not keep it awake for nothing: no background polling while the tab is hidden or the user is idle; the live channel and health pings do not count as activity; a small "still here?" prompt after long inactivity.

### Sync in real time (all through the same backend)
- Every change that matters (rate, settings, permissions, notification, app update, invoice, stock...) is written by the API and recorded as an **event** (`app_events`, sequence number, kept 7 days).
- **Live channel (SSE `/api/live`)**: connected apps and portal tabs receive the event within about a second and update the screen in place.
- **Closed apps:** the API sends an **FCM push** (existing Firebase setup). When the app is opened it asks "events after #N" and applies what it missed, so nothing is lost even if it was off for days.
- Website actions and app actions use the same code, so they produce identical events. Notifications, app updates and remote settings are composed on the portal and sent by the API (the server is awake because the admin is using the portal).

### Later: working-hours mode (not now)
The idle-stop time and a daily on/off schedule become settings in Admin Control (start at 09:00, stop at 21:00, keep on while anyone is active). Implemented with the same wake/stop scripts plus a scheduled trigger; no portal or app redesign needed.

### What changes in the earlier sections
- Sections 3, 4, 6: unchanged (PHP/Slim/Twig/HTMX/Tailwind, pages, Admin Control).
- Section 7 (backend changes): unchanged, and now the ONLY place logic is added (events, `/live`, app-config, audit, notification scheduling/inbox, web-session token, health/admin).
- Build order: Phase 0 (portal skeleton + login + wake screen, local), Phase 1 (realtime spine in Node + app listening), then the daily pages, reports/GST, Admin Control, hardening. Deployment to Hostinger only when you say.

### Hostinger checks (simpler now)
1. PHP 8.2 available on the plan (any plan works) and the ability to add a subdomain or folder (portal.laltuguineapalace.com), separate from the live PHP site.
2. Outbound HTTPS from Hostinger to `api.laltuguineapalace.com` and to the wake Lambda (normally allowed).
3. Config values (API base URL, wake URL) kept in a file outside the public folder. No database credentials are needed on Hostinger.

## 1. What it is for
The website is the **control room above the app**:
- Do everything the app does (billing, stock, old metal, orders, estimates, expenses, Day Book, dues, GST) from a big screen.
- Be the fallback when the app has a problem.
- Be the only place for **Admin Control**: staff and roles, branches, app updates, push notifications, app settings, audit log, backups.
- Everything the website changes reaches the phones **instantly**.

Daily pages must be self-explanatory (no training). Admin Control is separate, behind a stronger login.

## 2. Architecture (one rule: business rules live in ONE place)
```
 Browser (staff/owner)            Phone app (Flutter)
        |                                |
   PHP portal (BFF)                      |
        |  server-to-server              |
        +---------------> Node API <-----+        <- the ONLY code that touches the databases
                              |
                    MongoDB (dev now, prod later)
```
- The **Node API stays the single brain** (GST, discount floor, credit notes, valuation, branch scope, permissions). The PHP portal never talks to MongoDB and never re-implements a rule. So the app and the website can never disagree on a price or a tax figure.
- PHP is a **BFF (backend for frontend)**: it logs the user in against the API, keeps the API token in the PHP **session on the server** (never in browser JavaScript), renders pages and forwards actions.
- No public API-key platform (not wanted). Only two kinds of callers: the app and the portal, both signed in as real people.

## 3. Technology
| Part | Choice | Why |
|---|---|---|
| Language | PHP 8.2 | you asked for PHP; runs on the same EC2 or any cheap host |
| Structure | Slim 4 (routing) + Twig (templates) | light, fast, no heavy framework to learn; clean folders |
| Interactivity | HTMX + Alpine.js | pages update without page reloads, almost no JavaScript to maintain |
| Style | Tailwind CSS with the app's colours/cards | looks like the app (amber billing, teal Day Book, etc.) |
| Charts | Chart.js | Day Book, sales, GST trends |
| PDF | server-side from the API data (mPDF) matching the app's PDFs | invoices, credit notes, estimates, Day Book |
| Realtime in browser | Server-Sent Events (see 5) | no extra service |
Code lives in `F:\StockManagement\portal\` (new folder, same git repo).

## 4. Pages (self-UI, same look and words as the app)
Sidebar (left) like the reference software, but simpler: Home, Sell (GST Billing), Stock, Orders, Estimates, Old Metal, Purchases, Pending dues, Day Book, Expenses, Reports, GST, Customers/Suppliers, then **Admin Control** (visible only to Owner/Admin).
- **Home**: today's rate strip (edit in place, colour = set today / old / never), today's money in/out, dues, orders due, tally status, alerts.
- Every list: search, filters, export (Excel/PDF), keyboard shortcuts (F2 new bill, / search). Every form: 2 columns, floating labels, big buttons, live totals, same rules as the app.
- Bengali / English switch like the app.

### Admin Control (technical people only)
Staff and roles (permission grid), branches (the shop count grows here), GST settings and GSTIN, Stock Setting rules, **App updates** (latest version, force-update, release notes, APK link), **Send notification** (all / role / one person, schedule), **Remote settings** (see 6), audit log (who did what, when), server health (DB, disk, uptime, backup age), backups, integrations off.
Protection: role check on every route, re-enter password for risky actions, session timeout, optional 2-step code, every action written to the audit log.

## 5. Realtime sync (the important part)
Goal: something changed on the website (rate, settings, notification, update, permission) shows on every phone within about 1 second, and a phone that was offline catches up when it returns.

**Design: events + one live channel + push as a wake-up.**
1. **Event log.** Every change that matters is written by the API as an event `{seq, type, branchId, data, at}` into `app_events` (kept 7 days, auto-expiring). Types: `rate.changed`, `settings.changed`, `permissions.changed`, `notification.new`, `app.update`, `invoice.created`, `stock.changed`, `order.changed`, `expense.changed`, `tally.changed`.
2. **Live channel: Server-Sent Events** `GET /api/live?since=<seq>`. The API pushes each event as it happens. The app (background isolate not needed) and the browser both listen. It is one-way (server -> client), which is all we need, works through nginx, reconnects by itself, and needs no new server.
3. **Catch-up.** On reconnect the client sends the last `seq` it saw; the server replays what it missed. If the gap is bigger than 7 days the app simply refreshes its screens.
4. **Push (FCM) for closed apps.** When the app is not running, a push arrives ("Rate changed", "New update available"). Opening the app then does the catch-up. (FCM is already wired for notifications.)
5. **What the app does with an event:** updates the visible screen in place (new rate strip, permissions applied, a banner "Update available"), no manual refresh.
Because the website calls the same API, every website action automatically produces the same events as an app action. One mechanism, both directions.

Cost/safety notes: the server is stopped when idle to save money; live connections do **not** count as activity, so an open browser tab will not keep it awake. Live channel needs the auth token like every other call; events are branch-filtered per user.

## 6. Notifications, app updates, app settings from the website
- **Notifications**: compose title/message, audience (everyone, a role, a person, a branch), send now or later, see delivered/failed, history. Stored in-app as an inbox too (bell icon).
- **App updates**: set latest build number, minimum build (force update), notes, download link; the app shows the update dialog (existing) immediately via `app.update`.
- **Remote settings** (new, small): one `app_config` document versioned: feature switches (hide a module for staff), maintenance banner, rate-required-before-billing, default GST place, cash limit text, tablet layout, etc. The app reads it at start and on `settings.changed`.
- All of these go through the **existing** endpoints where they exist (`/notifications`, `/app-version`, `/permissions`, `/stock-settings`); only `/live`, `/app-config` and the audit log are new.

## 7. Backend changes needed (Node), all additive
1. `app_events` + event emitter used by the existing controllers (rates, expenses, orders, estimates, invoices, stock, tally, permissions, settings).
2. `GET /api/live` (SSE, auth, branch filter, `since` replay) and a small `GET /api/events?since=` for plain catch-up.
3. `app_config` model + `GET/PUT /api/app-config` (admin) + event.
4. Audit log: `app_audit` (who, what, when, before/after summary) written for admin actions; `GET /api/audit` (admin).
5. Notification scheduling and inbox endpoints; app-update fields (force/min build/notes).
6. Web session support: login endpoint variant that returns a refresh-safe token for the BFF (same users, same roles).
7. Health/admin endpoint for the server status card (disk, DB, uptime, last backup).
No existing collection is changed or deleted; new collections only.

## 8. Data and environments
- **Now: dev only.** Local Mongo `127.0.0.1:27018`: ONE dev database, `lgp_dev` (fake data from `seed-sample-history.js`; `jewellery_stock_dev` / `shopmanage_dev` / `clusterlgpadmin_dev` are old split-layout leftovers, safe to drop), plus `shopmanage` = a copy of the real production data for rehearsals. The production lines in `backend/.env` stay commented out. The portal runs on `http://localhost:8080` against the local API.
- **Later (only when you say):** the portal is deployed to the EC2 server behind nginx (`portal.laltuguineapalace.com` or `/admin`), the API is the same `api.laltuguineapalace.com`. Nothing about production changes without your explicit instruction. The live PHP website (`D:\LGPManagement`) is never touched.

## 9. Build order (each phase is usable and tested before the next)
0. **Foundation**: repo folder, PHP skeleton, login through the API, session, layout (sidebar, top bar with today's rate), theme matching the app, Bengali/English. Tests: login, roles, session expiry.
1. **Realtime spine** (Node): events, `/live`, catch-up, app listens (rate strip and notifications first). Test: change the rate on the portal, watch the phone update.
2. **Daily pages** in this order: Home + Rate, Stock (list, add/edit, boxes, tally), GST Billing (new invoice, list, PDF, payment, credit note), Old Metal, Orders, Estimates, Expenses, Day Book, Pending dues, Purchases.
3. **Reports and GST**: GST Summary, returns, ITC, monthly record, sales/stock reports, exports.
4. **Admin Control**: staff/roles/branches, app updates, notifications, remote settings, audit log, health.
5. **Hardening**: security review, backups, load check, browser tests, docs; deployment plan for you to run.

## 10. Testing approach
Every phase: API tests (existing smoke test + new sections), PHP feature tests against the local API, and a click-through on the browser and phone. Realtime test: a script that changes data through the portal while a listener asserts the event arrives in under 2 seconds and replays after a disconnect.

## 11. Decisions (answered)
1. Hosting: **Hostinger** (see Revision 1). 2. Role-based logins with the same users and DB as the app. 3. English first, Bengali gradually. Admin Control: Owner/Admin roles, password re-entry for risky actions.
4. **Reference screens**: used only for layout ideas (sidebar, rate strip, item panel with live price breakdown, Day Book, invoice list with column filters and export). Not copied feature-for-feature.
