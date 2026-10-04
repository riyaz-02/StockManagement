# API map (all under `/api`, JSON, `Authorization: Bearer <jwt>`)
**Branch scope:** every request runs in a branch context set by `protect`: staff see only their own branch; users with `branches.viewAll` / `billing.viewAllBranches` (admin, owner) see the firm, or one branch when the app sends header `X-Branch: <id|main>` (`all` = firm). New records are filed under that branch. Permission in [brackets]. Admin/owner bypass. Responses `{success, data|message}`. Details: read the route file.

| Mount | Purpose | Route file |
|---|---|---|
| `/auth` | `POST /login` (the `mobile` field takes a mobile number, a username or an e-mail: the people are the website's too), `GET /me`, `PUT /language`, `POST /register` (admin) | auth.routes |
| `/users`, `/permissions`, `/admin`, `/directory` | users, role/permission editor, admin console, customer/user directory | *.routes |

**People (one list for the app and the website):** `POST /auth/login {mobile, password}`: `mobile` may also be the person's username or e-mail (website logins), same password. `POST /users` and `PUT /users/:id` [users.manage] also take optional `username` and `email` (each must belong to one person, else 400 "Another person already has this username/email"); changing `mobile` moves the website's `contact` phone with it when it held the old number. The user JSON still has `name`, `mobile`, `isActive`, `profileImage` and now `username`, `email`. Details: `docs/DB_UNIFICATION.md`.
| `/containers`, `/items`, `/scan`, `/stock`, `/tally`, `/repair`, `/outward-movements`, `/inventory-snapshots`, `/bookings`, `/customers`, `/purchases` | inventory & operations | *.routes |
| `/tag-print`, `/tag-settings` | tag printing [tags.print / tags.manageSettings] | |
| `/reports`, `/analytics`, `/notifications`, `/settings`, `/app-version`, `/upload` | misc | |
| `/gst`, `/invoices` | legacy GST config/validators [gst.viewConfig]; old invoice API (unused by app since GST Invoice removal) | |
| **`/billing`** | invoicing (below) | billing.routes |
| **`/gst-reports`** | GST Summary (below) | gstReports.routes |

## /billing
- `GET /meta` [billing.view] – cashLimit, addressLimit, states, defaultPlace, supplyStateCode
- `GET /stats`, `GET /cash-today`, `GET /customer/:id` [billing.view]
- `GET /invoices`, `GET /invoices/:id` [billing.view]
- `POST /invoices` [billing.create] – body has `requestId` (idempotency), items, payments[], discount, extras, placeOfSupply
- `POST /invoices/:id/payments` [billing.receivePayment]; `POST /invoices/:id/print` [billing.view]

## /credit-notes
`GET /invoice/:id` [billing.view] per-line returnable state + notes; `POST /preview` and `POST /` [billing.creditNote] body `{requestId, invoiceId, lines:[{index, taxable?}], reason, note, refundMode, refundAmount}`; `GET /` (?invoice=&from=&to=), `GET /:id`. `GET /billing/last-making?name&metal&userWise=1`. `POST /preview` also returns `maxRefund` = the most that can be paid back (never above the note, never above what the customer paid minus refunds already made); `POST /` refuses a larger `refundAmount` (400).

## /billing extras
`POST /billing/reconcile` [billing.viewAllBranches]: returns stock / old metal of invoices cancelled elsewhere (also hourly).

## /old-metal
`GET /available?customerId&mobile&name` [billing.create] unused old metal of one customer. `POST /billing/invoices` accepts `oldMetalIds: [id]` (see BUSINESS_RULES).

`GET /` (?kind=old|raw&q=) [oldMetal.view] -> `{rows, totals}`; `POST /` and `POST /:id/cancel` [oldMetal.create]; `POST /calculate`. The server values the entry itself (`computeOldMetal`); the metal it brings in is counted by the stock reconciliation (there is no stock ledger).

## /stock-settings
`GET /` (any signed-in user) returns `{settings, defaults}`; `PUT /` partial update `{addStock:{valuation:'net'}, hallmark:{charge:60}}` and `POST /reset` need [settings.manageStockRules]. Values are whitelisted in `services/stockRules.js`.

## /gst-reports (all [gst.viewReports] unless noted)
`GET/PUT /settings` (PUT [gst.editSettings]) · `GET /summary` · `/register` · `/returns` (GSTR-1/3B + `checks`) · `/itc` · `/calendar` · `/export` (CSV) · `/monthly-record?year&month` · `GET/POST /filings`, `PUT /filings/:id` (writes [gst.manageFilings])

**GST registration:** all `/gst-reports` calls take `?gstin=` (empty = firm default GSTIN; `ALL` = add every registration up, only for summary/register/export). `settings`, `returns`, `itc`, `calendar`, `filings`, `monthly-record` need ONE GSTIN. `/settings` also returns `registrations[]`. Optional `branch=` narrows further.

Filters common to reports: period (`YYYY-MM` / `YYYY-Qn`), branch, dates, search, sort.

## /purchases (valuation)
One `purchases` list, shared with the PHP website (website field names are stored; the JSON below is unchanged: camelCase, lower-case `metalType`, `totalAmount` = taxable value, `totalPayable` = invoice total). New fields: `gstRecorded` (false for a purchase made on the old website: no GST / input credit counted), `websiteAttachment`, `source` (`app` | `website`). `DELETE /:id` removes the record for real (the website has no deleted flag) and keeps a copy in `app_trash`. The old `/api/invoices` CRUD route and its `invoices.*` permissions were removed (billing is `/api/billing`).
`POST /` with `valuation:{gross,less,net,purity,wastage,rate,labourRate,pieces,certification}` is valued by the server (`computePurchase`): goods (metal + labour) at the purchase GST, the hallmark fee (certification hallmarked/huid) added on top with its own GST (rule Purchase > Hallmark GST; CGST+SGST or IGST at the hallmark rates), all of it input credit. `PUT /:id` with `valuation` re-values the purchase (quantity, amount, GST, ITC, stock ledger); refused with 409 when the GSTR-3B of that period is already filed.

## /rates, /expenses, day book, dues
`GET /rates` (any user), `PUT /rates {gold?, silver?}` [rates.edit]. `GET /expenses?from&to` [expenses.view], `POST /expenses {amount, mode, category, note, date?}` [expenses.create], `DELETE /expenses/:id` [expenses.delete] (cancels). `GET /billing/daybook?from&to` [daybook.view]; `GET /billing/dues?q` [billing.view].

## /tally (additions)
`GET /preview` [tally.create] what a new tally would count; `GET /:id/summary` [tally.view] `{boxes, missing[], soldSince[], left}` (frozen lists once locked); `POST /` ignores typed totals; lock returns `missing` and `soldSince`.

## /billing/invoices (list)
`GET /invoices` rows carry `itemsSummary: {count, first, weight}` (what's on the bill, computed from the already-parsed `items`, not a separate query) alongside the existing summary fields.

## /estimates
`GET /?q&status` [estimates.view] - list rows carry `itemsSummary: {count, first, weight}` instead of the full `items`/`inputItems` (kept out of the list payload; use `GET /:id` for the full item lines). `GET /:id`; `POST /` {requestId, customerName, customerMobile, items[], goldRate, silverRate, discount, validDays, note} [estimates.create]; `POST /:id/converted {invoiceNumber}` [billing.create]; `DELETE /:id` cancels.

## /orders
`GET /?status=active|overdue|new|making|ready|delivered|cancelled&q` [orders.view] (+ `counts`); `GET /:id`; `POST /` [orders.create]; `POST /:id/advance {amount, mode}`; `POST /:id/status {status: making|ready, karigar?}`; `POST /:id/cancel {refundMode, refundAmount?, reason?}` [orders.cancel]. `POST /billing/invoices` accepts `orderId`.

## /live (realtime)
`GET /` SSE stream (Authorization header, or `?ticket=`; `?since=N` replays). Events: `hello {latest, reset}`, `rate.changed`, `settings.changed`, `permissions.changed`, `app.update`, `notification.new`, `data.changed {module}`; each `{seq, type, module, data, by, at}`. `GET /events?since=N&limit=` catch-up -> `{events, latest, reset}`. `POST /ticket` -> `{ticket, expiresInSeconds:60}`.

## /presence ("who's live", Admin Control > Staff & Roles)
In-memory only (`services/presence.js`; nothing written to Mongo — a server restart just clears it, which is fine for "right now" status). `POST /ping {platform: 'app'|'web', screen?}` [any signed-in user, same as `/live/ticket` — reports your OWN presence, no permission needed]: refreshes this user's entry (name/mobile/role/branch come from the token, not the body). `GET /` [users.manage]: `[{id, name, mobile, role, branchId, branchName, platform, screen, lastSeenAt, secondsAgo}]`, newest-active first; an entry not pinged in 90s is dropped. The app pings every ~20s while signed in and foregrounded (`lib/services/presence_service.dart`; `screen` is the top-most **named** route, set via `RouteSettings(name: ...)` on the module screens pushed from `home_screen.dart` — an unnamed sub-screen leaves the last known module showing rather than falling back to "Home"). The portal pings the same way from `app.js` (`screen` = the page's nav label, computed server-side in `app.twig`'s `data-screen`).

## /app-version (splash "update available" nudge, + the sign-in gate)
`GET /` public: `{latestVersion, latestVersionCode, forceUpdate, downloadUrl, updateMessage, maintenanceMode:{enabled,message}}`. `PUT /` [appUpdate.manage]: publish a version (as before). `PUT /maintenance {enabled, message}` [appUpdate.manage]: turns the sign-in gate on/off. When on, `POST /auth/login` refuses anyone who isn't admin/owner with `503 {message, maintenance:true}` — already-open sessions are untouched, only new sign-ins are blocked (both the app and the portal share this one login endpoint, so one toggle covers both).

## /notifications (the bell) and the app update pipeline
- `GET /api/notifications/feed?limit=&lang=en|bn` (any signed-in user) -> `{items:[{id, kind: notice|reminder, level: info|warn|bad|update, title, body, at, read, link: gst|tally|rate|update|'', source}], unread, reminders, seenAt}`. Notices = the `notifications` log filtered to this person (everyone, their role; admin/owner see all), last 30 days. Reminders = live checks (rate not set today, GST returns overdue / due soon, stock not tallied for 30 days), shown only to people with the matching permission. `POST /api/notifications/feed/seen` marks notices read. (`GET /` and `POST /send` stay admin-only.)
- `GET /api/app-version` (public) now also carries `apkFromServer, apkSha256, apkSize` and a relative `downloadUrl` (`/api/app-version/download`) once an APK was published; it never shows staged uploads or history.
- [appUpdate.manage] `GET /api/app-version/admin` (live + staged + last 10 releases), `POST /api/app-version/upload` (multipart, field `apk`, max 300 MB): reads package / versionName / versionCode from the APK, refuses a wrong package or a build number not above the live one, keeps it staged; `POST /api/app-version/publish {forceUpdate, updateMessage}`: makes the staged APK live (version, link, SHA-256), pushes to every device, emits `app.update` + `notification.new`, adds a bell notice, logs a release; `DELETE /api/app-version/staged`. Public `GET /api/app-version/download`: the published APK (`application/vnd.android.package-archive`, `X-Content-SHA256`, Range supported). `PUT /api/app-version` stays for an outside link.

## /billing (added for the website)
- `POST /api/billing/calculate` [billing.create]: body like `POST /billing/invoices` without customer (items, goldRate, silverRate, placeOfSupply, additionalCharges, discount, payments[], oldMetalIds[], orderId). Returns the computed bill (`totalPayableAmount`, `gstSummary`, `dueAmount`, `discountGiven`, `maxDiscount`, `tdsApplicable`...) plus `interstate`, `extraCredit` (old metal + order advance), `cashLimit`, `addressLimit`. Nothing is saved.
- Hallmark / HUID fee (rule `lgpmanagement-v3`): `items[].hallmarkCharge` (with `certification` hallmark|huid) is passed on AFTER the tax: not in `taxable_amount`, no GST on it; the calculate / create / view answers carry `hallmarkTotal`, each line `hallmarkCharge` + `hallmarkTaxed:false` (older bills: `true`, fee inside the taxable amount), and `line.total = taxable + GST + fee`. `gstSummary` never includes the fee; GST reports' invoice rows carry `hallmarkPassedOn`.
- `GET /api/billing/stock-line?code=&goldRate=&silverRate=` [billing.create]: a stock piece as an invoice line (`particulars, metalType, purity, netWt, grossWt, makingCharge, productCode, itemId, huid, certification, extras`), priced by the Stock Setting rules. 404 not found, 400 already sold/removed.
- `GET /api/items?limit=&page=`: paged (limit up to 200): `data.items`, `pagination {page,limit,total,hasMore}`, `totals {count, netWeight}`. Without `limit`: the whole list, as before. `POST/PUT /api/items` with `autoMaking:true` (+ `fixedMaking`) makes the server set `makingCharge` = labour + making (Stock Setting rules) + fixed.
- Purchases take an optional `invoiceTotal` (the total printed on the supplier's bill) on `calculate`, `create` and `PUT /purchases/:id`: the answer carries `roundOff`, `calculatedPayable` and `totalPayable` = the typed total; GST / ITC / TDS are unchanged; a difference above ₹50 is refused (400). On `PUT` alone it changes only the total (`''` clears it).
- `POST /api/purchases/calculate` [purchases.create]: body `{ metalType, quantity, rate, totalAmount?, transactionType?, valuation? }` -> `{ quantity, rate, totalAmount, valuation, cgstAmount, sgstAmount, igstAmount, totalGst, totalPayable, totalItc, tdsApplicable, tdsAmount, netPayable, ... }`. Nothing saved.
- `PUT /api/directory/customers/:id/partial` [directory.edit]: same body as the full update but only the fields to change; the rest is filled from what is stored. Returns the customer with profile.
- `GET /api/admin/audit?entity=&q=&from=&to=&page=&limit=` [admin/owner]: audit log lines `{entity, entityId, entityLabel, action, byName, at, changes[{field, from, to}]}` newest first + `pagination`. One shared log for every channel (app + website), since `services/audit.js` is called from inside the Node controllers, not from either client. `entity`: user | permission | app_update | notification | settings | customer | supplier | karigar | staff | invoice | credit_note | estimate | order | stock_item | purchase | old_metal | tally | expense | gst_filing. To add coverage for a new mutating endpoint: call `require('../services/audit').record(req, entity, entityId, label, action, changes)` right after the write succeeds (never `await`ed — a failed log line must not fail the request); add the new `entity` key to the portal's `AdminController::audit()` `kinds` map so it appears in the filter dropdown.
- `POST /api/admin/backup/inspect {uri}` [admin/owner]: connects to ANY MongoDB (the string is used for this call only: never stored, never logged, scrubbed from errors) and returns `{host, defaultDb, databases:[{name, isDefault, collections:[{name, type, count, sizeBytes}], totalDocs, totalBytes}]}` (system databases left out). `POST /api/admin/backup/download {uri, databases?:[name], includeReadable?:bool}` [admin/owner]: streams a `.zip` (`application/zip`); any refusal (bad address/password, unknown database, another backup running = 409) is a normal JSON error BEFORE the first file byte. Strictly read-only on the source (ping, listDatabases, listCollections, collStats, count, indexes, find only). Zip layout = `mongodump`'s: `dump/<db>/<coll>.bson` (exact bytes) + `.metadata.json` (indexes, options, view definitions), optional `readable/<db>/<coll>.jsonl`, `manifest.json` (counts + SHA-256 per file), `README-restore.txt`. One backup at a time. Role gate (`authorize('admin','owner')`), deliberately not a delegable permission. Audited as `entity: backup` (host + counts only). Restore: `mongorestore ... dump` or `node backend/scripts/restore-backup.js <unzipped> <uri> [--apply]` (plan first; only ADDS missing documents, never overwrites or drops).
- `GET /api/stock-settings` also returns `options` = the allowed values of every rule (and `hallmark.type`).

## /stock (stock = what is in the shop)
Stock is the barcoded pieces present (`items`) plus the explicit bulk entries (`bulk_weights`); no hand-kept ledger. All [stock.view] unless noted.
- `GET /dashboard` -> `{barcodedStock:{metal:{weightGrams,count}}, bulkWeights, bulkByCategory:{kind:{metal:g}}, totalStock:{metal:g}, asOf}`.
- `GET /bulk-weights` (?metalType, ?category, ?isActive) -> `{bulkWeights, categories}`; `POST /bulk-weights {metalType, weightGrams, description, category?, purity?, pieces?}`, `PUT /bulk-weights/:id {weightGrams?, description?, category?, purity?, pieces?, isActive?}`, `DELETE /bulk-weights/:id` [stock.manageBulkWeights]. `category` is one of `dust, parts, sub_items, raw, in_process, reserved, other`. Each change is audited (`bulk_stock`).
- `GET /reconciliation` -> `{reconciliation:{gold|silver:{totalPurchased, adjustedPurchase (x1.10 gold / x1.20 silver), oldMetalReceived, rawMetalBought, presentStock, barcodedStock, barcodedPieces, bulkStock, bulkEntries, totalSold, totalWastage, expectedDebit, discrepancy, hasAlert, alertMessage, ledgerTotal(=presentStock, for older phones)}}, anyAlert, alertThresholdGrams, wastageIncluded}`. expectedDebit = adjustedPurchase + old/raw metal - presentStock; discrepancy = expectedDebit - sold - wastage. Sold = every non-cancelled bill line in `invoices`; wastage = the website's approved `wastage_reports` (whole-firm view only).
- `GET /summary` [stock.view] -> the whole Summary: `{asOf, scope:{wholeFirm}, metals:{gold|silver:{receipts:{purchased, allowancePct, allowance, adjustedPurchase, oldMetal, rawMetal, total}, stock:{inShop, withOthers, bulk, total}, out:{soldGross, returned, sold, wastage}, pieces, bulkEntries, expectedOut, variance, variancePct, severity (normal|moderate|high), direction (short|excess|balanced)}}, checks:[{id, level (error|warn|info), count, grams, en, bn}], confidence:{level (reliable|check|fix), en, bn}, insights:{gold|silver:{severity, headline, analysis[], recommendations[]}} (each text `{en, bn}`), movements[], snapshot:{savedToday, todayInfo}, settings}`. All numbers are computed on the server in whole milligrams. A branch login sees its own branch only (`scope.wholeFirm=false`; wastage is a whole-firm record and is left out).
- `GET /summary/movements?limit=` [stock.view] -> `{movements:[{at, type (purchase|old_metal|raw_metal|sale|wastage|bulk), direction, metal, grams, title, note}]}`.
- `POST /summary/snapshot` [stock.snapshot, whole-firm login only] -> saves/updates today's snapshot built by the server (one per day; never overwrites a website snapshot). The server also takes it when the summary is first opened each day and nightly after 21:00 IST.
- `GET /summary/history?view=daily|weekly|monthly&from=&to=` [stock.view] -> `{rows:[{label, date, basis, snapshots, methodChange, gold|silver:{stock, in, out, variance, variancePct, severity}}] (newest first), trend:{enough, comparable, ...}}`; `GET /summary/history.csv` the same as a file.
- `GET /wastage` (?status=pending|approved|rejected, ?metal, ?category, ?from, ?to, ?q, page, limit) [wastage.view] -> `{reports, pagination, totals:{approved, pending}, categories}`; `GET /wastage/:id`; `POST /wastage {date, metal, amount, category, reason, remarks}` and `PUT /wastage/:id` (only while waiting, by the reporter or admin/owner) [wastage.report]; `POST /wastage/:id/approve {comment}` and `POST /wastage/:id/reject {comment (required)}` [wastage.approve, admin by default]. A report counts only once approved; the reporter cannot approve their own (admin/owner can); an approval can be reversed only by admin/owner. Documents are the website's `wastage_reports` shape. Settings `reconcile` in `/stock-settings` (allowance %, thresholds).
- `GET /daily-summary?startDate&endDate&metalType` -> `{summary:{date:{metal:{in,out,net}}}, from, to}` (default last 31 days): in = purchases + old/raw metal, out = bills + approved wastage.
- Removed: `PUT /items/:id/sell` (the quick-sale record) and the `items.sell` permission: a piece is sold on a GST bill, which marks it sold.

## GST filings and records (one collection each)
`/gst-reports/filings` (GET, POST, PUT /:id) now read and write the website's `gst_data` (one document per FY quarter); a filing looks the same as before plus `source` (`app` | `website`: records the old site made show as GSTR-1 / GSTR-3B filings of their quarter). POST for a return already recorded (by either side) is 409. The generated monthly GST record is logged in the website's `outputDoc`.
