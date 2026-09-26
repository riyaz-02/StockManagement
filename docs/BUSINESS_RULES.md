# Business rules (source of truth is the engines; this is the spec)

## Billing v2 — rule id `lgpmanagement-v2` (`services/billingCalc.js`; legacy v1 = discount after GST, kept for old invoices)
- Line taxable = netWt × rate + making + stones + hallmark. A typed taxable override is allowed but never below metal value.
- GST 3%: CGST 1.5% + SGST 1.5% (intra-state) or IGST 3% (place of supply ≠ supplier state). Default place: West Bengal, changeable to any state (codes in `services/gstStates.js`).
- Extra charges (packing, courier…) are taxed at the same rate (CGST Act s.15(2)(c)).
- **Discount before GST**: taken from making (or hidden making inside a typed taxable), never from metal/stones/hallmark → exact payable = bill − discount. Max via `maxDiscount`. Payable rounded to rupee.
- TDS 1% flag when payable > ₹2,00,000 (PAN required). Rule 46(f): buyer address required at ≥ ₹50,000 (`ADDRESS_LIMIT`).
- **Cash limit s.269ST**: < ₹2,00,000 cash per person per day (server `CASH_LIMIT` 200000, "≥" blocked; app shows 1,99,999). Split `payments[]` (cash + UPI/card/etc.) is the legal way to take more.
- Numbering: atomic via `shop_info`; requestId makes creates idempotent.

## Branches & GSTINs
- Staff work in their own branch; admins can see the firm or switch to a branch (`X-Branch`). Old records without a branch are `main`.
- One GSTIN = one set of returns, ITC ledger, due dates, filing frequency, reminders. Invoices/purchases are assigned to a registration through their branch. Branch invoice numbers: `PREFIX-0001`; main keeps the website's plain series.
- Not built yet: moving stock between branches (transfer), per-branch purchase ITC split beyond branchId.

## Returns, refunds, credit notes (CGST Act s.34, Rule 53)
- A return / price cut / deficiency after a sale is a **credit note** against the original invoice (never edit or delete the invoice). It must show: supplier + GSTIN, note number and date, the original invoice number and date, the recipient's name, address and state (unregistered buyer), items with HSN, taxable value and tax.
- Tax on the note = tax that was charged on the credited value (CGST+SGST or IGST as on the invoice). Partial return / part refund = a smaller taxable amount on the line.
- The shop may reduce its tax liability for the note only if the note is declared (GSTR-1 table 9B) **by 30 November following the financial year of the invoice** (or the annual return date, if earlier). After that it is still a valid note for the customer but the tax cannot be reduced (`reducesTax=false`, not deducted in GST Summary). B2C buyers have no input credit to reverse, so no reversal is needed.
- Refund payment: the credit note does not itself limit the mode; refunds are recorded with mode and amount. Cash-payment limits for businesses (Income-tax s.40A(3)) and the s.269ST receipt limit are not applied to refunds by the app: ask the CA about large cash refunds.
- Exchange = credit note for the returned piece + a new invoice for the new piece (or old metal adjusted).
- Open CA questions: GST treatment of a deduction/retention kept from a refund; TCS/TDS reversal on returned sales.

## Old metal on a bill
Value of received old metal (Stock Setting > Old Metal basis) is a payment in kind: bill total and GST are unchanged, `paid_amount` includes it, cash-limit (s.269ST) counts only Cash lines. Open CA questions: GST/RCM on old metal bought from unregistered persons; TDS on the exchange.

## Stock valuation (Stock Setting rules)
See the header of `backend/services/stockValuation.js`. Bases: finalFine | fine | net | gross. Rules live in `app_stock_settings` (firm-wide) and are served by `/api/stock-settings`.

## GST reporting (`services/gstReports.js`)
- Periods monthly `YYYY-MM` or quarterly `YYYY-Qn`; FY from April. Due dates per period; periods before `settings.remindersFrom` are "untracked".
- ITC utilisation order: IGST credit→IGST,CGST,SGST; CGST credit→CGST,IGST; SGST credit→SGST,IGST.
- Reminders: once per lead time, hourly job + boot catch-up.
- `complianceChecks`: address ≥50k, PAN >2L, place of supply, HSN, cash ≥2L/day, numbering gaps, B2CL, untaxed extras on legacy invoices.
- Monthly "GST Invoice Record" PDF mirrors the website layout (`lib/utils/gst_record_pdf.dart`, data from `/monthly-record`).

## Open compliance questions (for the CA)
Place of supply for over-the-counter buyers from other states (customer state auto-followed); B2B buyer GSTIN not captured (all sales B2C); website's "1% TDS >₹2L" legal basis and TCS 206C(1H) not handled; ITC comes from purchase records not GSTR-2B; extra charges/discount-after-GST on legacy invoices; website's annual PDF/xls export not ported; unique index on `invoices.invoice_number` recommended, not created.

## Purchase hallmark fee and editing a purchase
- Purchase valuation: goods taxable = metal + labour (3% GST). A hallmark fee (per piece or per gram, from the Hallmark settings) is a separate service charge: it carries its own GST (9+9 / 18) when the Purchase rule "Hallmark GST" is on, none when off; the fee and its GST are input credit.
- A credit note refund can never exceed what the customer paid (a bill with a round-off is paid a few paise below taxable + tax), nor the refunds already made on the invoice.
- A purchase's valuation can be edited (amount, GST, ITC and the stock ledger are re-worked) until the GSTR-3B of its period is filed; after that a correction belongs in the next return.

