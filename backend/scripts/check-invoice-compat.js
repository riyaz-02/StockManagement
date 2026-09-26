/**
 * check-invoice-compat.js — READ-ONLY check of the billing engine against real
 * invoices in the live `invoices` collection.
 *
 *   SOURCE_URI=mongodb+srv://.../shopmanage node scripts/check-invoice-compat.js [--verbose]
 *
 * For every invoice it recomputes the line values and totals from the stored
 * inputs (weight, rate, making, additional charges, discount) with
 * services/billingCalc.js and compares them with what was saved. It also runs
 * every document through the app's list/detail mapper, so anything the app
 * could not display is reported. Nothing is written.
 */
'use strict';

const { MongoClient } = require('mongodb');
const { computeInvoice } = require('../services/billingCalc');
const { toView } = require('../services/billingView');

const URI = process.env.SOURCE_URI;
if (!URI) { console.error('Set SOURCE_URI (database name included).'); process.exit(2); }
const VERBOSE = process.argv.includes('--verbose');
const close = (a, b) => Math.abs(Number(a) - Number(b)) < 0.011;

(async () => {
    const c = new MongoClient(URI);
    await c.connect();
    const docs = await c.db().collection('invoices').find({}).toArray();

    const out = { total: docs.length, bulk: 0, checked: 0, typedTaxable: 0, lineMismatch: [], totalMismatch: [], payableMismatch: [], roundOffMismatch: [], viewErrors: [], statuses: {} };

    for (const d of docs) {
        out.statuses[d.status || '(none)'] = (out.statuses[d.status || '(none)'] || 0) + 1;
        try {
            const v = toView(d);
            if (!v.invoiceNumber || !Array.isArray(v.items)) throw new Error('missing number/items');
        } catch (e) { out.viewErrors.push(`${d.invoice_number}: ${e.message}`); }

        const items = Array.isArray(d.items) ? d.items : [];
        if (!items.length || items.every((i) => !Number(i.rate))) { out.bulk++; continue; }   // hand-written block bills carry no rates

        const r = computeInvoice({
            items: items.map((i) => ({
                particulars: i.particulars || 'x', metalType: i.metal_type, netWt: i.net_wt, rate: i.rate,
                makingCharge: i.making_charge, hsnCode: i.hsn_code,
                // staff sometimes type the taxable amount by hand (negotiated price): replay that
                taxableOverride: Math.abs(Number(i.net_wt) * Number(i.rate) + Number(i.making_charge) - Number(i.taxable_amount)) > 0.011 ? i.taxable_amount : undefined,
            })),
            additionalCharges: d.additional_charges, discount: d.discount, paidAmount: d.paid_amount, discountMode: 'after_gst',
        });
        if (!r.ok) { out.viewErrors.push(`${d.invoice_number}: engine refused (${r.error})`); continue; }
        out.checked++;
        if (items.some((i) => Math.abs(Number(i.net_wt) * Number(i.rate) + Number(i.making_charge) - Number(i.taxable_amount)) > 0.011)) out.typedTaxable++;

        items.forEach((i, k) => {
            const l = r.items[k];
            if (!l) return;
            const bad = ['taxable_amount', 'cgst', 'sgst', 'total'].filter((f) => !close(l[f], i[f]));
            if (bad.length) out.lineMismatch.push(`${d.invoice_number} item ${k + 1}: ${bad.map((f) => `${f} stored ${i[f]} vs ${l[f]}`).join(', ')}`);
        });
        if (!close(r.totalAmount, d.total_amount)) out.totalMismatch.push(`${d.invoice_number}: total_amount stored ${d.total_amount} vs ${r.totalAmount}`);
        if (!close(r.totalPayableAmount, d.total_payable_amount)) out.payableMismatch.push(`${d.invoice_number}: payable stored ${d.total_payable_amount} vs ${r.totalPayableAmount}`);
        else if (!close(r.roundOff, d.round_off)) out.roundOffMismatch.push(`${d.invoice_number}: round_off stored ${d.round_off} vs ${r.roundOff}`);
    }

    const pct = (n) => (out.checked ? ((100 * (out.checked - n)) / out.checked).toFixed(1) : '-');
    console.log(`\nInvoices in collection:      ${out.total}`);
    console.log(`Hand-written block bills:    ${out.bulk} (no rates, skipped)`);
    console.log(`Recomputed with the engine:  ${out.checked}`);
    console.log(`  (of which staff typed the taxable: ${out.typedTaxable})`);
    console.log(`  line values match:         ${pct(new Set(out.lineMismatch.map((x) => x.split(' ')[0])).size)}%  (${out.lineMismatch.length} lines differ)`);
    console.log(`  total_amount matches:      ${pct(out.totalMismatch.length)}%`);
    console.log(`  total_payable matches:     ${pct(out.payableMismatch.length)}%`);
    console.log(`  round_off matches:         ${pct(out.roundOffMismatch.length)}%`);
    console.log(`App mapper problems:         ${out.viewErrors.length}`);
    console.log(`Statuses:                    ${JSON.stringify(out.statuses)}`);
    for (const [k, list] of Object.entries({ lineMismatch: out.lineMismatch, totalMismatch: out.totalMismatch, payableMismatch: out.payableMismatch, roundOffMismatch: out.roundOffMismatch, viewErrors: out.viewErrors })) {
        if (list.length) { console.log(`\n${k} (${list.length})`); list.slice(0, VERBOSE ? 200 : 8).forEach((x) => console.log('  - ' + x)); }
    }
    await c.close();
})().catch((e) => { console.error('failed:', e.message); process.exit(1); });
