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
| Login / roles / permissions | done | `/auth`, `/permissions` | secure token storage on web |
| GST Billing create (3 steps, split pay, discount, HUID, scan) | done | `/billing/meta`, `POST /billing/invoices` | scan → typed product code / webcam later |
| Invoice list/detail/PDF/payments | done | `/billing/invoices*` | PDF via printing |
| GST Summary (6 tabs, filters, ITC, calendar, filings, reminders, checks) | done | `/gst-reports/*` | CSV via Blob download |
| Monthly GST Invoice Record PDF (landscape, full item/payment detail, audit breakdown) | done | `/gst-reports/monthly-record` | rebuild the layout in PHP |
| Branch switcher (admins) + per-branch stock | done | header `X-Branch`, `/directory/branches` | dropdown in the site header |
| GST registrations (per-GSTIN returns/ITC/filings) | done | `?gstin=` on `/gst-reports/*` | selector on the GST page |
| Item & box add/edit wizards (3 steps, Cloudinary photos) | done | `POST/PUT /items`, `POST/PUT /containers` | same steps as a PHP form wizard; `PUT /items/:id` with `containerId`/`slotNumber` moves the item |
| Purchase with valuation (weights, purity, wastage, labour, hallmark fee + its GST), edit valuation until GSTR-3B filed | done | `POST/PUT /purchases` (`valuation`) | server computes; the site only sends the inputs |
| Long-press invoice menu (open, share, print, receive payment, credit note) | done | `/billing/invoices/:id`, `/credit-notes` | row action menu on the invoice list |
| Today's rate, Expenses, Day Book, Pending dues | done | `/rates`, `/expenses`, `/billing/daybook`, `/billing/dues` | simple pages; rate strip in the header |
| Estimates (quotations, PDF, make invoice) | done | `/estimates` | same item lines as an invoice |
| Stock tally (auto snapshot, box-by-box, missing list) | done | `/tally/*` | scan by typed barcode on web |
| Customer orders (advance, karigar, delivery, deliver-and-bill) | done | `/orders`, `orderId` on invoices | order list + detail pages |
| Inventory: items/containers/tally/repair/booking | done | `/items` `/containers` … | not yet reviewed for web |
| Tag printing | done | `/tag-print` | printing plugin |
| Push notifications | done | `/notifications` | web push optional |
| User directory / admin console | done | `/directory`, `/admin` | admin console already web-like |

## Testing the PHP site
Backend suites are the contract (`docs/DEV_TESTING.md`). Manual pass per feature: billing -> PDF -> payment -> GST Summary. The site must never write to production while testing (dev DB only).
