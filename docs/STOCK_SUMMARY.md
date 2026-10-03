# Stock Summary (metal balance and discrepancy)

The website's `D:\LGPManagement\pages\summary` page (Summary, Daily Stock Analysis = `calcHistory`, wastage reports) is rebuilt for the app and the new website on top of the ONE database and the barcode / tally stock. Same data, same numbers, both clients (`GET /api/stock/summary`).

## What the old page did
- Per metal (gold / silver): purchases, purchases x 1.10 (gold) / x 1.20 (silver), "physical stock" (from the hand-kept stock ledger), expected issuance, sold on GST bills, approved wastage, and the **discrepancy** = adjusted purchase - ledger stock - sold - wastage, shown with its percentage of the adjusted purchase.
- Insights (Bengali): normal below 1.5 %, moderate below 5 %, high above.
- A daily snapshot (button, numbers sent by the browser) kept in `daily_snapshots`; a history page (daily / weekly / monthly, charts, CSV, print); recent stock movements; wastage reports (pending / approved / rejected).

## The balance (what the new calculation does)
Everything is computed on the server from the shop's own records, in whole milligrams (no floating point drift), never from numbers a client sends.

Per metal:
```
Receipts   = purchases x (1 + allowance %)  +  old metal taken in  +  raw metal bought
Stock      = pieces in the shop  +  pieces out (repair / agent / customer)  +  bulk stock
Out        = sold on bills (net of returns put back)  +  approved wastage
Variance   = Receipts - (Stock + Out)            positive: metal not accounted for     negative: more than the records explain
Variance % = Variance / Receipts
```
- **Allowance** (default gold 10 %, silver 20 %, the old website's figures) is the weight gained when bullion is alloyed into jewellery. It is a setting (Stock settings > Stock check), not a hidden constant.
- **Sold** = every bill line that is not cancelled / void, minus the weight of returned pieces that were put back into stock (credit notes with `restocked`). A cancelled bill is never a sale (the old page counted it).
- **Pieces out** (`in_repair`, `UNDER_REPAIR`, `repair`, `WITH_CUSTOMER`, `WITH_AGENT`, `temporarily_removed`) still belong to the business, so they count as stock (shown on their own line); otherwise a piece sent for repair would show as missing metal.
- **Wastage** counts only when approved. Pending / rejected reports are shown but not counted. The person who reports a wastage cannot approve their own report (admin / owner can).
- **Severity** (settings, default): normal below 1.5 %, moderate below 5 %, high from 5 %; a variance of 1 g or less is always normal.
- Not in stock and not sold: pieces removed (deleted) from the app. They are listed so a wrongly removed piece is visible.

## Foolproofing
- Data checks next to the result: bills with no weight or an unknown metal, purchases with no weight, pieces with zero weight, cancelled bills whose pieces were never put back, sold pieces with no bill, returns larger than sales, duplicate bill numbers, wastage waiting for approval, stale or missing stock tally, removed pieces, no bulk stock entered, a branch-only view (wastage not included). Each says what it means and what to do. The result carries a confidence line: reliable / check these first.
- Insights are built from those findings (not generic text): which pieces or reports could explain the gap, what to enter or approve, what to count.
- Daily snapshot: built by the server, one per day (saving again the same day updates it), taken automatically when the summary is first opened each day and by a nightly job; a manual button remains. The old website's snapshots are kept and shown.
- History: weekly / monthly rows use the LAST snapshot of the period for balances and the CHANGE between period ends for in / out (the old page averaged snapshots and showed running totals as "in" and "out"). The old snapshots were based on the hand-kept ledger; the history marks the day the method changed.

## Collections (one per operation)
`daily_snapshots` (website's, shape kept: `date`, `gold`/`silver` {purchase_total, calculated_purchase, stock_total, expected_stock_debit, total_sold, final_result, discrepancy_percentage}; the app adds fields beside them), `wastage_reports` (website's, shape kept), `purchases`, `invoices`, `items`, `bulk_weights`, `app_old_metal`, `app_credit_notes`, settings in `app_stock_settings`.

## API
`GET /stock/summary`, `GET /stock/summary/history`, `GET /stock/summary/movements`, `POST /stock/summary/snapshot`; wastage: `GET/POST /stock/wastage`, `GET/PUT /stock/wastage/:id`, `POST /stock/wastage/:id/approve|reject`. Details in `docs/API.md`.
