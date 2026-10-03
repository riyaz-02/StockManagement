# One database for the app and the website

**Decision (owner):** the phone app and the website are two ways into the SAME data. The website's structure (in use for 1.5 years) is the master; the app adapts to it. One database, one list of people (`users`), one list of customers (`customers`).

## Layout (target)
One database, the website's `shopmanage`. Nothing the website uses is moved or renamed; the app's collections are added next to them.

| Who owns it | Collections | Notes |
|---|---|---|
| **Shared by design** | `users`, `customers`, `invoices`, `purchases`, `gst_data`, `outputDoc` | the website's shape is the stored shape; the app adapts and only adds fields (people; purchases: GST split; gst_data: `filings`) or rows (invoices, outputDoc) in the website's shape |
| **Website only** | `daily_snapshots`, `inventory`, `newyear_invite_2026`, `sales`, `settings`, `shop_info` (invoice numbering, shared), `stock_entries`, `stock_log`, `suppliers`, `temp_customer_uploads`, `wastage_reports` (read by the app's stock check) | the app never writes to these (guard list `WEBSITE_ONLY` in `scripts/merge-app-into-website-db.js`). `stock_entries` is the website's manual stock ledger: the app does not use it (stock = items present + bulk) |
| **App only** | `items`, `containers`, `tallysessions`, `bookings`, `notifications`, `outwardmovements`, `repairlogs`, `rolepermissions`, `inventorysnapshots`, `appversions`, `scheduledjobstates`, `bulk_weights`, `gst_configs`, `app_old_metal`, `app_credit_notes`, `app_orders`, `app_estimates`, `app_expenses`, `app_rates`, and the other `app_*` | operations the website has no equivalent of. Retired (not copied by the merge, nothing reads them): `sales` / `app_sales` (quick-sell), `app_gst_filings` (-> `gst_data`), `app_gst_documents` (-> `outputDoc`), `app_stock_entries`, `app_legacy_invoices`, `app_purchases` |

`config/db.js`: ONE address (`MONGODB_URI`, must end with the database name; the server refuses to start without one) and ONE connection (`getConnection()`, = `mongoose.connection`). `SHOPMANAGE_DB_URI` / `LGP_ADMIN_DB_URI` and the three-handle design are gone (ignored if still set). Collections the website owns are never created or re-indexed by the app: their models say `autoIndex:false, autoCreate:false` and raw access goes through `getConnection().db`.

**One list per operation (rule):** the server and the database are one; the web and the app are only two ways of working on them. So an operation has ONE collection, in the website's shape, and every client goes through the one API.
- **Purchases = `purchases`** (done): stored as the website stores them (`invoice_date` text, `invoice_number`, `metal_type` 'Gold', `total_amount` = invoice total with GST ...); the app's GST split, valuation and attachments are extra fields beside them. `models/Purchase.js` `toApp()` shows the app and the portal the same JSON as before. An old website purchase has no GST split, so it is shown with its invoice total and no GST / input credit (`gstRecorded:false`); a split the website later invalidates (it edited `total_amount`) is ignored the same way. The website has no "deleted" flag, so a delete in the app removes the record for real and keeps a full copy in `app_trash`. API fields are unchanged; new: `gstRecorded`, `websiteAttachment`, `source`.
- **Invoices = `invoices`** (done): the older camelCase invoice route / model (`/api/invoices`, used by neither the app nor the portal) was removed; all billing goes through `/api/billing` in the website's shape.
- **Stock** (done): there is no stock ledger. Stock = the pieces present (`items`, barcode + tally) + explicit bulk entries (`bulk_weights`, with a kind: dust / parts / sub-items / raw / in-process / reserved). The check compares purchases (+10% gold / +20% silver) + old/raw metal taken in against present stock + sold (bills) + approved wastage (the website's formula, with its hand-kept ledger replaced by what is really present). On the real data the new formula reproduces the website's own difference once the missing bulk metal (about 320 g of gold in the barcoded count) is entered as Bulk stock.
- **GST filed returns** (done): the website's `gst_data` is the single list: the old records show as filings, a return filed in the app is stored in the same quarter document and the website's flags are kept in step, so the old site shows it filed too. PMT-06, GSTR-9, monthly returns and other GSTINs live in that document's `filings`.
- **Generated GST records** (done): `outputDoc` (the app's `app_gst_documents` is retired).
- **Quick-sell** (done): retired; a sale is an invoice (the app's Sell button already opens a GST bill with the piece).

## People (`users`)
Stored with the website's field names (`username`, `email`, `password`, `full_name`, `role`, `contact`, `is_active`, `status`, `created_at` ...), because the PHP site reads and writes exactly those. The app adds `mobile`, `branchId`, `branchName`, `permissionOverrides`, `language`, `fcmTokens`, `legacyAppIds`, `source`; the website ignores them. `models/User.js` exposes the app's old names as aliases of the stored fields (`name` = `full_name`, `isActive` = `is_active`): one value, so deactivating someone on either side switches them off on both.
- **One password:** PHP `password_hash` (`$2y$`) and bcryptjs (`$2a$`) verify each other (tested). Change it on either side, it changes everywhere.
- **Sign-in:** the app by mobile, then username, then e-mail; the website unchanged (username / e-mail).
- **Roles:** the website writes `admin` / `Admin` / `manager` / `staff` / `user`; reading is case-insensitive, an unknown role has no app permissions (safe default). The website itself only checks "admin or not": it has no permissions, so anyone with a login can use every legacy website page (decide whether to add a check, see Open decisions).
- **Merge:** an app user is matched to a website user by phone (`contact`, last 10 digits). A match KEEPS the website's name, password and role and only gains the app fields (+ `legacyAppIds` = the old app id, so a phone still holding an old token keeps working: `middleware/auth.js`). No match = added in the website's format with the same `_id` and password hash. A number shared by two website users is listed, never guessed.

## Customers (`customers`)
The website's record is the master. `services/customerStore.js` is the one place the app finds / creates customers:
- found by ANY of `whatsapp_no`, `mobile_no`, `mobile_no_3`, `mobile_no_4` (and the app profile's `contacts`), never a deleted one;
- created exactly like the website's "add customer" page: `sl_no` = highest among customers NOT deleted + 1 (and never one in use), `is_deleted:false`, `notification_type`, `created_by(_name)`, `source`;
- an existing customer is never changed by a booking / wishlist / sale (names and addresses are edited only through the directory, which checks the record has not changed and writes an audit line);
- what only the app knows (customer code, wishlist, bookings, richer details) lives in `app_customer_profiles`, keyed by `customerId`. The old app `Customer` model (`jewellery_stock.customers`) is gone.

## Doing the merge (production is NOT touched until the owner says so)
1. **Backup everything** with Admin Control > Data backup (zip, mongodump format). Keep a copy off this computer.
2. **Rehearse on a clone:** restore the backup into the LOCAL mongod (`node scripts/restore-backup.js <unzipped> mongodb://127.0.0.1:27018 --apply --into <name> --only <db>`), then
   `node scripts/merge-app-into-website-db.js mongodb://127.0.0.1:27018/<app db copy> mongodb://127.0.0.1:27018/<website db copy> --report plan.json` (a PLAN: nothing written). Read the report: matched people, role conflicts (`--roles website` is the default and keeps the website's role), people needing a decision, customers matched / new / skipped. Then `--apply` on the copy and run the app against it (`MONGODB_URI` = the copy).
3. **Cutover** (only on the owner's word): sign-in gate on (App updates page; Admin/Owner exempt) for a short freeze; final backup of both databases; `merge ... --apply --allow-remote` into `shopmanage` (insert-only, the website keeps working throughout); deploy the new backend with ONE `MONGODB_URI` (delete the other two); smoke-test; gate off.
4. **Afterwards:** keep the old app database read-only for ~a month; roll back by pointing the old release back at it within the first day (after that, roll forward: new data exists only in `shopmanage`); rotate the Atlas password (it is hard-coded in the website's `includes/dbconfig.php`).

The merge is idempotent (running it again adds nothing), never writes to the source, refuses to write to a non-local target without `--allow-remote`, and refuses to copy anything into a collection the website uses.

## Tests
`node scripts/user-model.test.js`, `node scripts/db-merge.test.js` (fixtures shaped like production: byte-identical website data, matched / new / shared-number people, customers matched by any number, idempotent, source untouched, and the new models on the merged DB), `node scripts/api-smoke.js` (500, now against ONE database). The dev environment is already merged: `lgp_dev` (see `backend/.env`).

## Rehearsal on the real production backup (2026-10-03, local copy only)
Backup `lgp-backup-clusterlgpadmin...-20261002-195205.zip` (jewellery_stock + shopmanage) restored into local `rehearsal_app` / `rehearsal_web`, plan then `--apply` on the copy: **website data byte-identical** (all 16 website collections incl. 2340 customers, 375 invoices, 107 purchases: 0 missing, 0 changed; `users` 12 -> 13 with 3 enriched), source untouched, 23 app collections added (items 798, containers 53, tally sessions 5, settings 7 ...). App customers in production: 0 (no customer merge needed). People: 3 matched (Sk Riyaz, Sk Sadhin, "Sk Laltu" 9831292885 = website "Sekh Nazir": confirm it is the same person), 1 new (Sk Laltu 7003067971), 0 ambiguous, 0 role conflicts. Sign-in lookups checked on the merged copy (mobile and username; website `$2y$` hashes). Website-only staff whose phone is only in `contact` can also sign in on the app with it (when unique).

## Local final database (2026-10-03)
Local `shopmanage` (127.0.0.1:27018) = the production website database (restored from the 2 Oct backup) + the app data merged in with the tool above, exactly the steps production will get: website collections 0 missing / 0 changed, `users` 12 -> 13 (3 enriched), 23 app collections added (items 798, containers 53 ...), second run adds nothing, backend boots on it ("One database: shopmanage"). It holds REAL customer data and real password hashes: keep it on this computer, do not run `api-smoke.js` / the seed against it (they reset invoices); tests keep using `lgp_dev`. To work on it: `$env:MONGODB_URI='mongodb://127.0.0.1:27018/shopmanage'; node server.js` (the production passwords are not the dev ones). `rehearsal_app` (the restored app database, the merge source) and `rehearsal_web` stay as scratch copies.

## Production merge APPLIED (2026-10-03, copy step only)
`clusterlgpadmin` (production Atlas): a read-only backup was taken first (`E:\lgp-backup-clusterlgpadmin...-20261003-050216.zip`, 44 files verified against the manifest hashes, byte-identical to the 2 Oct one), the plan was read, then `jewellery_stock` -> `shopmanage` was applied insert-only with the same tool. Verified by a SHA-1 fingerprint of every document before and after: all 16 other website collections have 0 missing / 0 changed documents (customers 2340, invoices 375, purchases 107 ...), `users` 12 -> 13 (3 enriched: Sk Riyaz, Sekh Nazir = app "Sk Laltu" 9831292885, Sk Sadhin; 1 new: Sk Laltu 7003067971), 23 app collections added (items 798, containers 53 ...), source `jewellery_stock` identical, a second run adds nothing. **Still to do (owner):** switch the server's `.env` to the single `MONGODB_URI` ending `/shopmanage` and deploy (the old backend keeps writing to `jewellery_stock` until then: re-run the same merge after the deploy to catch up anything written in the gap).

## Indexes the merge adds on website collections
The merge creates ONE index on a website collection: `users.mobile_1` (unique, sparse), so a mobile number belongs to one person. The PHP site never writes `mobile`, so it is unaffected. Nothing else on a website collection is created, changed or dropped.

## Open decisions (owner)
1. **Website access (owner said yes, 2026-10-03: app users MAY sign in to the legacy site; no change made there):** the legacy PHP site has no permissions beyond admin / not. Shared users can therefore log in there and see everything. Leave as is (all app users are trusted staff), or add a small `website_access` check to the site's login (a change to the live site, deployed with the cutover).
2. **Matching (approved 2026-10-03):** by phone (`contact` ↔ `mobile`) with a report to approve before anything is written. People the report lists as "needs a decision" must be resolved by hand.
3. **Roles in a conflict (approved: keep the website's):** default keeps the WEBSITE's role (website is the master); `--roles higher` keeps the higher of the two.
4. **Purchases:** DONE (single `purchases`).
5. **Stock ledger:** DONE (see above; owner: manual stock in / out is obsolete, stock follows the items present, bulk entered explicitly).
6. **GST filings:** DONE (single `gst_data`).
7. **Quick-sell:** DONE (retired).
