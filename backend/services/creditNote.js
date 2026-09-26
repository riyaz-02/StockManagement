/**
 * creditNote.js - the maths and the rules of a GST credit note (sales return / refund / price adjustment).
 *
 * Law (CGST Act s.34, Rule 53):
 *  - A credit note is issued by the supplier when goods are returned, or the price was too high, or the goods were
 *    deficient. It states the ORIGINAL invoice, the items / value credited and the tax on it, and (for an unregistered
 *    buyer) the buyer's name, address and state.
 *  - It reduces the supplier's tax liability only if it is declared (GSTR-1 table 9B) before 30 November following the
 *    end of the financial year of the invoice, or the date of the annual return, whichever is earlier. A note made
 *    later is still valid between shop and customer, but the shop can NOT reduce its tax for it.
 *  - For an unregistered (B2C) buyer there is no input credit to reverse, so the supplier may reduce the tax.
 *  - The tax on the note is the tax that was charged on the credited value (same CGST+SGST or IGST as the invoice).
 *
 * A credit note is per line of the invoice: the full taxable value of the line (return of the piece) or any smaller amount
 * (partial return / price adjustment). Notes already made on a line reduce what can still be credited on it.
 */
'use strict';

const r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };

const REASONS = ['sales_return', 'price_adjustment', 'quality_issue', 'exchange', 'other'];

/** Financial-year start year of a YYYY-MM-DD date (April to March). */
function fyStart(ymd) {
    const [y, m] = String(ymd).split('-').map(Number);
    return m >= 4 ? y : y - 1;
}

/** Last day the tax on a note for this invoice can still be reduced: 30 November after the financial year of the invoice. */
function deadline(invoiceYmd) {
    return `${fyStart(invoiceYmd) + 1}-11-30`;
}

/**
 * @param invoice  a document of the invoices collection (snake_case)
 * @param asked    [{ index, taxable? }]  the invoice lines to credit (taxable = amount to credit; default: all that is left)
 * @param prior    { [index]: taxable already credited by earlier notes }
 */
function compute(invoice, asked, prior = {}) {
    const items = Array.isArray(invoice.items) ? invoice.items : [];
    const inter = String(invoice.gst_type || '') === 'IGST' || items.some((l) => num(l.igst) > 0);
    const lines = [];
    for (const a of Array.isArray(asked) ? asked : []) {
        const idx = Number(a && a.index);
        const line = Number.isInteger(idx) ? items[idx] : null;
        if (!line) return { ok: false, error: `Line ${a && a.index} is not on this invoice` };
        const lineTaxable = r2(num(line.taxable_amount));
        const left = r2(lineTaxable - num(prior[idx]));
        if (!(left > 0.004)) return { ok: false, error: `${line.particulars || 'Item'} has already been credited in full` };
        let taxable = a.taxable === undefined || a.taxable === null || a.taxable === '' ? left : r2(a.taxable);
        if (!(taxable > 0)) return { ok: false, error: `Enter an amount above 0 for ${line.particulars || 'the item'}` };
        if (taxable > left + 0.004) return { ok: false, error: `${line.particulars || 'Item'}: at most ${left.toFixed(2)} can still be credited` };
        taxable = Math.min(taxable, left);
        const full = Math.abs(taxable - left) < 0.005 && Math.abs(left - lineTaxable) < 0.005;   // the whole line, nothing credited before
        const cgst = inter ? 0 : r2(taxable * 0.015);
        const sgst = inter ? 0 : r2(taxable * 0.015);
        const igst = inter ? r2(taxable * 0.03) : 0;
        lines.push({
            index: idx, particulars: String(line.particulars || line.particular || ''), hsn: String(line.hsn_code || ''), metal: String(line.metal_type || ''),
            netWt: num(line.net_wt), purity: String(line.purity || ''), productCode: String(line.product_code || ''), itemId: String(line.item_id || ''),
            lineTaxable, taxable, cgst, sgst, igst, total: r2(taxable + cgst + sgst + igst), fullReturn: full,
        });
    }
    if (!lines.length) return { ok: false, error: 'Choose at least one item to credit' };
    const sum = (k) => r2(lines.reduce((a, l) => a + l[k], 0));
    return { ok: true, gstType: inter ? 'IGST' : 'CGST_SGST', lines, taxable: sum('taxable'), cgst: sum('cgst'), sgst: sum('sgst'), igst: sum('igst'), total: sum('total') };
}

/** Can the note still reduce the shop's tax? (declared before the deadline of the invoice's financial year) */
function reducesTax(invoiceYmd, noteYmd) {
    return String(noteYmd) <= deadline(invoiceYmd);
}

module.exports = { REASONS, compute, deadline, reducesTax, fyStart, r2 };
