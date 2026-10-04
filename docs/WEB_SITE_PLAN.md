# Website (fallback for when the Android app fails) — living plan
**Update the feature table after every app feature.** Goal: staff can bill, check stock and file GST from any browser using the same backend.

## Decision (owner, 2026-09): the website will be built in **PHP**, with all the features of the app
Not Flutter Web. The PHP site is a second client of the SAME REST API (`docs/API.md`), so no business rule is re-implemented: totals, GST, cash limit, numbering all come from the server. Build it after the Android app is complete. Priority: 1 login/permissions -> 2 billing (create, list, detail, PDF, payments) -> 3 item lookup -> 4 GST Summary -> 5 stock/containers -> rest.
Notes for the PHP client: send `Authorization: Bearer <jwt>` (+ optional `X-Branch`, `?gstin=`); JWT is issued by `POST /api/auth/login` (keep it in a server-side session, never in JS-readable storage); the pure engines (`backend/services/billingCalc.js`) can be ported for live totals in the browser, but the server recomputes and is the truth (400 on bad input); PDFs (invoice, monthly GST record) are built client-side in the app today: on the web use a PHP PDF library (TCPDF/mPDF/Dompdf) from the JSON of `/billing/invoices/:id` and `/gst-reports/monthly-record`, following `flutter_app/lib/utils/invoice_pdf.dart` and `gst_record_pdf.dart` for the layout (fixed point-width columns, one block per invoice, no shared widgets).

## Setup needed
- Server-side PHP calls the API (no CORS needed); if any browser JS calls it directly add the origin to `CORS_ORIGIN`. The EC2 auto-stop/Lambda wake flow (`server_startup_screen`) must be called by the PHP site too before its first request.

## Feature status (app → web)
| Feature | App | Key endpoints | Web notes |
|---|---|---|---|
| Data backup (paste a MongoDB address, download every record raw + restore) | web only (Admin Control) | `/admin/backup/inspect`, `/admin/backup/download` | done in the portal: `/admin/backup`; Admin/Owner only; read-only; mongodump-format zip |
| Login / roles / permissions | done | `/auth`, `/permissions` | secure token storage on web |
| Common users (app + website): sign in by mobile / username / e-mail, one password, Username + E-mail on Staff & Roles | done (dev) | `/auth/login`, `PUT /users/:id` | production merge awaits the owner (`docs/DB_UNIFICATION.md`) |
| GST Billing create (3 steps, split pay, discount, HUID, scan) | done | `/billing/meta`, `POST /billing/invoices` | scan → typed product code / webcam later |
| Invoice list/detail/PDF/payments | done | `/billing/invoices*` | PDF via printing |
| GST Summary (6 tabs, filters, ITC, calendar, filings, reminders, checks) | done | `/gst-reports/*` | CSV via Blob download |
| Monthly GST Invoice Record PDF (landscape, full item/payment detail, audit breakdown) | done | `/gst-reports/monthly-record` | rebuild the layout in PHP |
| Branch switcher (admins) + per-branch stock | done | header `X-Branch`, `/directory/branches` | dropdown in the site header |
| GST registrations (per-GSTIN returns/ITC/filings) | done | `?gstin=` on `/gst-reports/*` | selector on the GST page |
| Item & box add/edit wizards (3 steps, Cloudinary photos) | done | `POST/PUT /items`, `POST/PUT /containers` | same steps as a PHP form wizard; `PUT /items/:id` with `containerId`/`slotNumber` moves the item |
| Hallmark / HUID fee on a bill: passed on after tax, no GST on it (rule v3), own row on totals / invoice / PDF / GST record | done (app + web) | `POST /billing/invoices`, `POST /billing/calculate` (`hallmarkTotal`, line `hallmarkTaxed`) | engine `billingCalc.js` + Dart mirror + portal JS; older bills unchanged |
| Purchase invoice total editable (supplier's round-off), fixed later, GST unchanged | done (app + web) | `invoiceTotal` on `/purchases/calculate`, `/purchases`, `PUT /purchases/:id` | web: field + round-off rows + "Change the invoice total"; app: Add/Edit Purchase |
| Camera scanners: fast, zoom, torch, queued tally scans | done (app) | `POST /tally/:id/scan` | `widgets/fast_scanner.dart` |
| Notification bell: sent notices + live reminders (rate, GST due, stock tally, app update), unread number, opens a list | done (app + web) | `/notifications/feed`, `/feed/seen` | web: top bar, `/partials/bell/*`; app: Home header sheet |
| App updates by upload: upload the APK, checked + staged, publish, push to every phone, in-app download + install, release history | done (app + web) | `/app-version/upload|publish|admin|download` | web: Admin > App updates; procedure `docs/APP_RELEASE.md` |
| Add / edit customer: pop-up, up to 6 numbers, live duplicate check on every number, Bengali name + address fill themselves, four message choices, special dates (birthday, anniversary ...), referral, "+ New customer" inside a bill | done (website pop-up, app form, shared API) | `/directory/customers*`, `/directory/lookup`, `/directory/translate` | same data as the old website (`address_bengali`, `notification_type`, `mobile_no_3/4`) |
| Several branches + billing counters: open / change / switch off a branch, its counters, who works where, counter on bills + payments + estimates/orders/credit notes, branch + counter picker | done (backend, app Settings > Branches & counters, website Admin Control > Branches & counters + top-bar Working at) | `/branches*`, `X-Counter`, `counterId` on bills | existing data stays main branch with no counter |
| App sign-in: remembered phone (90 days, refreshed on every open), 4-digit passcode, fingerprint, "Forgot passcode", pictures on the sign-in screen uploaded on the website | done (app + website page `/admin/login-screen`) | `/auth/refresh`, `/app-assets/login-slides*` | the website's own sign-in is unchanged |
| Uploads (photos, PDFs, videos) to Amazon S3 with small copies; Cloudinary links keep working; delete from either | done (backend + app; website shows the pictures) | `/upload/*`, `/purchases/upload-bill` | `docs/S3_SETUP.md`; needs the bucket + EC2 role created in AWS |
| Purchase with valuation (weights, purity, wastage, labour, hallmark fee + its GST), edit valuation until GSTR-3B filed | done | `POST/PUT /purchases` (`valuation`) | server computes; the site only sends the inputs |
| Long-press invoice menu (open, share, print, receive payment, credit note) | done | `/billing/invoices/:id`, `/credit-notes` | row action menu on the invoice list |
| Today's rate, Expenses, Day Book, Pending dues | done | `/rates`, `/expenses`, `/billing/daybook`, `/billing/dues` | simple pages; rate strip in the header |
| Estimates (quotations, PDF, make invoice) | done | `/estimates` | same item lines as an invoice |
| Stock tally (auto snapshot, box-by-box, missing list) | done | `/tally/*` | scan by typed barcode on web |
| Bulk stock (dust, parts, sub-items, raw, in-process: explicit entries counted as stock) + "Check the stock" (purchases + old/raw metal vs present, sold, wastage) | done (app + web) | `/stock/bulk-weights`, `/stock/reconciliation` | web: Stock page panels; stock = items present + bulk, no manual ledger |
| Stock Summary: metal balance (receipts vs stock + sold + approved wastage), difference + level, data checks, confidence, insights, movements, daily snapshot, history (daily/weekly/monthly, CSV), wastage reports with approval | done (app + web) | `/stock/summary*`, `/stock/wastage*` | web: Stock Summary menu, `/stock/summary`, `/stock/summary/history`, `/stock/wastage`; app: Store > Summary tab, history and wastage screens; spec `docs/STOCK_SUMMARY.md` |
| GST filed returns in the website's `gst_data` (old records visible, new ones added to the same quarter document) | done | `/gst-reports/filings` | one list for app, web and the old site |
| Customer orders (advance, karigar, delivery, deliver-and-bill) | done | `/orders`, `orderId` on invoices | order list + detail pages |
| Inventory: items/containers/tally/repair/booking | done | `/items` `/containers` … | not yet reviewed for web |
| Tag printing | done | `/tag-print` | printing plugin |
| Push notifications | done | `/notifications` | web push optional |
| User directory / admin console | done | `/directory`, `/admin` | admin console already web-like |
| Web portal: Day Book, Expenses, Dues, Orders, Old Metal, GST Billing, Estimates | built in `portal/` | `/billing/calculate`, `/billing/stock-line` + existing | see `docs/WEB_PORTAL_PLAN.md`; stock/tally/GST/admin pages follow |

## Testing the PHP site
Backend suites are the contract (`docs/DEV_TESTING.md`). Manual pass per feature: billing -> PDF -> payment -> GST Summary. The site must never write to production while testing (dev DB only).
