# API map (all under `/api`, JSON, `Authorization: Bearer <jwt>`)
**Branch scope:** every request runs in a branch context set by `protect`: staff see only their own branch; users with `branches.viewAll` / `billing.viewAllBranches` (admin, owner) see the firm, or one branch when the app sends header `X-Branch: <id|main>` (`all` = firm). New records are filed under that branch. Permission in [brackets]. Admin/owner bypass. Responses `{success, data|message}`. Details: read the route file.

| Mount | Purpose | Route file |
|---|---|---|
| `/auth` | `POST /login`, `GET /me`, `PUT /language`, `POST /register` (admin) | auth.routes |
| `/users`, `/permissions`, `/admin`, `/directory` | users, role/permission editor, admin console, customer/user directory | *.routes |
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

`GET /` (?kind=old|raw&q=) [oldMetal.view] -> `{rows, totals}`; `POST /` and `POST /:id/cancel` [oldMetal.create]; `POST /calculate`. The server values the entry itself (`computeOldMetal`) and credits the stock ledger.

## /stock-settings
`GET /` (any signed-in user) returns `{settings, defaults}`; `PUT /` partial update `{addStock:{valuation:'net'}, hallmark:{charge:60}}` and `POST /reset` need [settings.manageStockRules]. Values are whitelisted in `services/stockRules.js`.

## /gst-reports (all [gst.viewReports] unless noted)
`GET/PUT /settings` (PUT [gst.editSettings]) · `GET /summary` · `/register` · `/returns` (GSTR-1/3B + `checks`) · `/itc` · `/calendar` · `/export` (CSV) · `/monthly-record?year&month` · `GET/POST /filings`, `PUT /filings/:id` (writes [gst.manageFilings])

**GST registration:** all `/gst-reports` calls take `?gstin=` (empty = firm default GSTIN; `ALL` = add every registration up, only for summary/register/export). `settings`, `returns`, `itc`, `calendar`, `filings`, `monthly-record` need ONE GSTIN. `/settings` also returns `registrations[]`. Optional `branch=` narrows further.

Filters common to reports: period (`YYYY-MM` / `YYYY-Qn`), branch, dates, search, sort.

## /purchases (valuation)
`POST /` with `valuation:{gross,less,net,purity,wastage,rate,labourRate,pieces,certification}` is valued by the server (`computePurchase`): goods (metal + labour) at the purchase GST, the hallmark fee (certification hallmarked/huid) added on top with its own GST (rule Purchase > Hallmark GST; CGST+SGST or IGST at the hallmark rates), all of it input credit. `PUT /:id` with `valuation` re-values the purchase (quantity, amount, GST, ITC, stock ledger); refused with 409 when the GSTR-3B of that period is already filed.

## /rates, /expenses, day book, dues
`GET /rates` (any user), `PUT /rates {gold?, silver?}` [rates.edit]. `GET /expenses?from&to` [expenses.view], `POST /expenses {amount, mode, category, note, date?}` [expenses.create], `DELETE /expenses/:id` [expenses.delete] (cancels). `GET /billing/daybook?from&to` [daybook.view]; `GET /billing/dues?q` [billing.view].

## /tally (additions)
`GET /preview` [tally.create] what a new tally would count; `GET /:id/summary` [tally.view] `{boxes, missing[], soldSince[], left}` (frozen lists once locked); `POST /` ignores typed totals; lock returns `missing` and `soldSince`.

## /estimates
`GET /?q&status` [estimates.view]; `GET /:id`; `POST /` {requestId, customerName, customerMobile, items[], goldRate, silverRate, discount, validDays, note} [estimates.create]; `POST /:id/converted {invoiceNumber}` [billing.create]; `DELETE /:id` cancels.

## /orders
`GET /?status=active|overdue|new|making|ready|delivered|cancelled&q` [orders.view] (+ `counts`); `GET /:id`; `POST /` [orders.create]; `POST /:id/advance {amount, mode}`; `POST /:id/status {status: making|ready, karigar?}`; `POST /:id/cancel {refundMode, refundAmount?, reason?}` [orders.cancel]. `POST /billing/invoices` accepts `orderId`.
