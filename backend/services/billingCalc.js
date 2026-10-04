/**
 * billingCalc.js — GST invoice maths, "lgpmanagement-v1".
 *
 * Copied from the LIVE billing page (D:\LGPManagement, pages/billing/index.php)
 * and checked against real invoices, so an invoice made in the app is
 * numerically identical to one made on the website:
 *
 *   per line   taxable = netWt x rate + makingCharge      (or a typed override)
 *              CGST = SGST = taxable x 1.5%
 *              total = taxable + CGST + SGST              (each shown to 2 dp)
 *   DISCOUNT (this app, rule v2): taken off BEFORE GST, as the GST Act (s.15(3)(a)) and Rule 46 expect:
 *              the customer-facing discount is converted to a reduction of the taxable value and GST
 *              follows it down, so the payable is exactly (bill - discount). It is taken from the making
 *              charge first (or, on a typed-taxable line with making 0, from the amount above metal +
 *              stones + hallmark), NEVER from the metal, stones or hallmark. A typed taxable amount
 *              below the metal value is refused.
 *   invoice    itemsTotal   = sum of the line totals (as shown, 2 dp)
 *              total_amount = itemsTotal + additionalCharges
 *              payable      = round( itemsTotal + additionalCharges - discount )
 *                             to the nearest RUPEE
 *              round_off    = payable - (itemsTotal + additional - discount)
 *              due_advance  = paid - payable    (negative = customer owes us)
 *   TDS        payable > Rs 2,00,000  ->  1% of payable, customer PAN required
 *   hallmark / an item may be Hallmarked or carry a HUID. The hallmarking centre has ALREADY charged GST on its
 *   HUID       fee, so the charge is passed on as it is: it is NOT part of the taxable value and carries no GST
 *              (rule v3). It is added to the line AFTER the tax, so line total = taxable + GST + hallmark charge,
 *              and it is never discounted. Bills made before v3 (rule v2) had it inside the taxable amount.
 *              The invoice name reads "Ring (Hallmarked)" or "Ring (HUID: AB12CD)".
 *   stones /   an item may carry extras (stone, diamond, another metal) with a weight and a
 *   other      value; the value is added to the taxable amount of that line.
 *   metals     (the website has no such field: it only ever stored the resulting taxable amount)
 *   other      when the place of supply is in another state the tax is IGST 3% instead of
 *   state      CGST 1.5% + SGST 1.5%. The line total is the same; the website never produced
 *              IGST, so these invoices are an app-only addition (cgst/sgst are stored as 0).
 *
 * Real example (invoice 1401): 0.08 g @ 9190 + making 64 -> line 823.18;
 * additional 55, discount 78 -> total_amount 878.18, payable 800, round_off -0.18.
 *
 * NOTE (tax treatment): like the website, the discount is subtracted AFTER GST.
 * If it should reduce the taxable value instead, change it here (one place)
 * under a new RULE id so old invoices stay reproducible.
 *
 * The server is the source of truth: it recomputes from the raw inputs and
 * never trusts totals sent by a client (the website does).
 */
'use strict';

const RULE = 'lgpmanagement-v3';               // discount before GST + hallmark charge outside the taxable value (this app)
const RULE_LEGACY = 'lgpmanagement-v1';        // the website's old rule: discount after GST
const GST_HALF = 0.015;
const GST_FULL = 0.03;
const TDS_THRESHOLD = 200000;
const TDS_RATE = 1;
const DEFAULT_HSN = '7113';

const num = (v) => {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
};
const r2 = (n) => Math.round((num(n) + Number.EPSILON) * 100) / 100;
const r3 = (n) => Math.round((num(n) + Number.EPSILON) * 1000) / 1000;

const LIMITS = { maxItems: 50, maxWeight: 100000, maxRate: 10000000, maxMoney: 1000000000 };
const METALS = ['Gold', 'Silver', 'Other'];

/** How an item is named on the invoice: "Ring", "Ring (Hallmarked)" or "Ring (HUID: AB12CD)". */
function composeParticulars(base, certification, huid) {
    const b = String(base || '').trim();
    if (certification === 'huid' && huid) return `${b} (HUID: ${huid})`;
    if (certification === 'huid' || certification === 'hallmark') return `${b} (Hallmarked)`;
    return b;
}

const metalOf = (v) => {
    const s = String(v || '').toLowerCase();
    return s.startsWith('s') ? 'Silver' : s.startsWith('o') ? 'Other' : 'Gold';
};

/**
 * @param {object} input {items[], goldRate, silverRate, additionalCharges, discount, paidAmount}
 * @returns {{ok:true, ...} | {ok:false, error:string}}
 */
function computeInvoice(input) {
    const legacy = input.discountMode === 'after_gst';          // the website's old rule: discount off the total, after GST
    const interstate = input.interstate === true;
    const gold = r2(input.goldRate);
    const silver = r2(input.silverRate);
    const additionalCharges = r2(Math.max(0, num(input.additionalCharges)));
    const discountAsked = r2(Math.max(0, num(input.discount)));
    const items = Array.isArray(input.items) ? input.items : [];

    // Extra charges (courier, packing...) are part of the value of supply (CGST Act s.15(2)(c)), so they carry GST
    // at the same rate as the goods. The old website rule left them untaxed.
    const addCg = legacy || interstate ? 0 : additionalCharges * GST_HALF;
    const addSg = legacy || interstate ? 0 : additionalCharges * GST_HALF;
    const addIg = legacy || !interstate ? 0 : additionalCharges * GST_FULL;
    const addTotal = r2(additionalCharges + addCg + addSg + addIg);
    const addTaxable = legacy ? 0 : additionalCharges;

    if (!items.length) return { ok: false, error: 'Add at least one item' };
    if (items.length > LIMITS.maxItems) return { ok: false, error: `An invoice can have at most ${LIMITS.maxItems} items` };

    // ── 1. validate every item and work out its numbers BEFORE any discount ──
    const base = [];
    for (let i = 0; i < items.length; i++) {
        const it = items[i] || {};
        const n = i + 1;
        const particulars = String(it.particulars || it.particular || '').trim();
        if (!particulars) return { ok: false, error: `Item ${n}: enter what is being sold` };
        const metalType = metalOf(it.metalType);
        const netWt = r3(it.netWt);
        if (!(netWt > 0)) return { ok: false, error: `Item ${n}: net weight must be more than 0` };
        if (netWt > LIMITS.maxWeight) return { ok: false, error: `Item ${n}: weight is too large` };
        const fallback = metalType === 'Gold' ? gold : metalType === 'Silver' ? silver : 0;
        const rate = r2(num(it.rate) || fallback);
        if (!(rate > 0)) return { ok: false, error: `Item ${n}: enter the ${metalType.toLowerCase()} rate` };
        if (rate > LIMITS.maxRate) return { ok: false, error: `Item ${n}: rate is too large` };
        const makingCharge = r2(Math.max(0, num(it.makingCharge)));

        // gross weight is optional, but net can never exceed it
        const grossWt = r3(it.grossWt);
        if (grossWt > 0 && netWt > grossWt + 0.0005) return { ok: false, error: `Item ${n}: net weight cannot be more than gross weight` };

        // stones / other metals inside the piece
        const extras = [];
        for (const e of (Array.isArray(it.extras) ? it.extras : []).slice(0, 10)) {
            const amount = r2(Math.max(0, num(e && e.amount)));
            const weight = r3(Math.max(0, num(e && e.weight)));
            const name = String((e && e.name) || '').trim().slice(0, 60);
            const kind = ['Stone', 'Diamond', 'Pearl', 'Metal', 'Other'].includes(e && e.kind) ? e.kind : 'Stone';
            if (!name && !amount && !weight) continue;
            extras.push({ kind, name, weight, amount });
        }
        const extrasAmount = r2(extras.reduce((a, e) => a + e.amount, 0));

        // hallmark / HUID: the centre's fee already carries its GST, so it is passed on after tax (never taxed again);
        // the certification is also part of the name printed on the invoice
        const huid = String(it.huid || '').trim().toUpperCase().slice(0, 20);
        const certification = it.certification === 'hallmark' || it.certification === 'huid' ? it.certification : (huid ? 'huid' : '');
        if (certification === 'huid' && !/^[A-Z0-9]{6}$/.test(huid)) return { ok: false, error: `Item ${n}: HUID must be 6 letters or digits` };
        const hallmarkCharge = certification ? r2(Math.max(0, num(it.hallmarkCharge))) : 0;

        const metalRaw = netWt * rate;                                   // what the metal itself is worth today
        const preTax = extrasAmount;                                     // stones: taxable, never discounted (the hallmark charge sits outside the taxable value)
        const overridden = it.taxableOverride !== undefined && it.taxableOverride !== null && String(it.taxableOverride).trim() !== '';
        const taxable0 = overridden ? r2(it.taxableOverride) : metalRaw + makingCharge + preTax;
        if (overridden && !(taxable0 > 0)) return { ok: false, error: `Item ${n}: taxable amount must be more than 0` };
        if (!legacy && overridden && Math.round(taxable0 * 100) < Math.round(metalRaw * 100)) {
            return { ok: false, error: `Item ${n}: taxable amount cannot be below the metal value (₹${r2(metalRaw).toFixed(2)})` };
        }
        // how much of this line can ever be discounted: only what is above metal + stones
        // (the making charge, or the making charge hidden inside a typed taxable amount)
        // With no making charge on the line (and no typed taxable amount) the discount comes off the total, but never
        // below the metal value; with a making charge, only that making charge can be discounted.
        const noMaking = !overridden && !(makingCharge > 0);
        const floorRaw = noMaking ? metalRaw : metalRaw + preTax;
        const headroom = legacy ? 0 : Math.max(0, Math.round(taxable0 * 100) - Math.round(floorRaw * 100));   // in paise

        base.push({
            n, particulars: particulars.slice(0, 160), metalType, netWt, rate, makingCharge, grossWt, extras, extrasAmount,
            huid, certification, hallmarkCharge, overridden, taxable0, metalRaw, floorRaw, headroom,
            hsn: String(it.hsnCode || DEFAULT_HSN).slice(0, 8),
            purity: String(it.purity || '').trim().slice(0, 12),
            productCode: String(it.productCode || '').trim().slice(0, 40),
            itemId: String(it.itemId || '').trim().slice(0, 40),
        });
    }

    // ── 2. one line, given the part of the discount (in paise) that lands on it ──
    const buildLine = (b, dPaise) => {
        const taxableRaw = b.taxable0 - dPaise / 100;
        const cgstRaw = interstate ? 0 : taxableRaw * GST_HALF;
        const sgstRaw = interstate ? 0 : taxableRaw * GST_HALF;
        const igstRaw = interstate ? taxableRaw * GST_FULL : 0;
        const total = r2(taxableRaw + cgstRaw + sgstRaw + igstRaw + b.hallmarkCharge);   // hallmark charge: after tax, no GST on it
        // typed taxable amount: the making charge lives inside it, so the making column is 0 and the name says so
        const making = legacy ? b.makingCharge : (b.overridden ? 0 : r2(Math.max(0, b.makingCharge - dPaise / 100)));
        const hiddenMaking = !legacy && b.overridden && Math.round(taxableRaw * 100) > Math.round(b.floorRaw * 100);
        const name = composeParticulars(b.particulars, b.certification, b.huid) + (hiddenMaking ? ' + Making Charge' : '');
        const line = {
            particulars: name.slice(0, 200),
            hsn_code: b.hsn,
            metal_type: b.metalType,
            net_wt: b.netWt,
            rate: b.rate,
            making_charge: making,
            taxable_amount: r2(taxableRaw),
            cgst: r2(cgstRaw),
            sgst: r2(sgstRaw),
            total,
        };
        // additive detail, only written when present (the website ignores unknown fields)
        if (interstate) line.igst = r2(igstRaw);
        if (b.purity) line.purity = b.purity;
        if (b.grossWt > 0) line.gross_wt = b.grossWt;
        if (b.productCode) line.product_code = b.productCode;
        if (b.itemId) line.item_id = b.itemId;
        if (b.certification) {
            line.certification = b.certification;
            if (b.huid) line.huid = b.huid;
            if (b.hallmarkCharge > 0) { line.hallmark_charge = b.hallmarkCharge; line.hallmark_in_taxable = false; }
        }
        if (b.certification || hiddenMaking) line.item_name = b.particulars;
        if (b.extras.length) { line.extras = b.extras; line.stone_charge = b.extrasAmount; }
        if (dPaise > 0) line.discount = dPaise / 100;
        return line;
    };

    // spread a pre-tax discount over the lines that have something discountable, in proportion to it
    const sumHp = base.reduce((a, b) => a + b.headroom, 0);
    const allocate = (dtPaise) => {
        const alloc = base.map(() => 0);
        if (dtPaise <= 0 || sumHp <= 0) return alloc;
        const frac = [];
        let given = 0;
        base.forEach((b, i) => {
            const share = (dtPaise * b.headroom) / sumHp;
            const f = Math.min(b.headroom, Math.floor(share));
            alloc[i] = f;
            given += f;
            frac.push([share - f, i]);
        });
        let rem = dtPaise - given;
        frac.sort((x, y) => y[0] - x[0]);
        while (rem > 0) {
            let moved = false;
            for (const [, i] of frac) {
                if (rem <= 0) break;
                if (alloc[i] < base[i].headroom) { alloc[i]++; rem--; moved = true; }
            }
            if (!moved) break;
        }
        return alloc;
    };
    const linesFor = (alloc) => base.map((b, i) => buildLine(b, alloc[i]));
    const sum = (arr, f) => arr.reduce((a, x) => a + f(x), 0);

    // ── 3. the bill before any discount ──
    const lines0 = linesFor(base.map(() => 0));
    const before0 = sum(lines0, (l) => l.total) + addTotal;
    const bill0 = Math.round(before0);                              // what the customer would pay with no discount
    const ro0 = bill0 - before0;
    const metalValue = r2(sum(base, (b) => b.metalRaw));
    const hallmarkTotal = r2(sum(base, (b) => b.hallmarkCharge));   // passed-on hallmark / HUID fees: inside the total, outside the taxable value
    // the most that can be taken off what the customer pays, leaving metal + stones + hallmark untouched
    const maxDiscount = legacy ? 0 : Math.max(0, Math.floor((sumHp / 100) * (1 + GST_FULL) + ro0 - 0.02));

    let lines = lines0;
    let discountBeforeGst = 0;
    if (legacy) {
        if (before0 - discountAsked < 0) return { ok: false, error: 'Discount cannot be more than the bill total' };
    } else if (discountAsked > 0) {
        if (discountAsked > maxDiscount) {
            return {
                ok: false,
                error: maxDiscount > 0
                    ? `Discount is too high. At most ₹${maxDiscount} can be given: the price cannot go below the metal, stone and hallmark value`
                    : 'No discount is possible on this bill: there is no making charge above the metal value',
                maxDiscount,
            };
        }
        // Discount is taken off the taxable value BEFORE GST (GST Act s.15(3)(a)); GST then follows it down.
        // Solve for the pre-tax discount that makes the customer's payable exactly (bill - discount).
        const target = Math.round(bill0 - discountAsked);
        const start = Math.round(((discountAsked - ro0) / (1 + GST_FULL)) * 100);
        let best = null;
        for (let k = 0; k <= 12 && !best; k++) {
            for (const sgn of k === 0 ? [0] : [1, -1]) {
                const p = Math.max(0, Math.min(sumHp, start + sgn * k));
                const alloc = allocate(p);
                const cand = linesFor(alloc);
                const pay = Math.round(sum(cand, (l) => l.total) + addTotal);
                if (pay === target) { best = { alloc, cand, p }; break; }
            }
        }
        if (!best) return { ok: false, error: 'Could not fit that discount exactly. Try a slightly different amount', maxDiscount };
        lines = best.cand;
        discountBeforeGst = best.p / 100;
    }

    // ── 4. totals ──
    const itemsTotal = sum(lines, (l) => l.total);                  // the website sums the rounded line totals
    const sumTaxable = sum(lines, (l) => l.taxable_amount) + addTaxable;
    const sumCgst = sum(lines, (l) => l.cgst) + r2(addCg);
    const sumSgst = sum(lines, (l) => l.sgst) + r2(addSg);
    const sumIgst = sum(lines, (l) => l.igst || 0) + r2(addIg);
    const grossTaxable = r2(sum(base, (b) => b.taxable0));

    const totalAmount = r2(itemsTotal + addTotal);
    const before = itemsTotal + addTotal - (legacy ? discountAsked : 0);
    if (totalAmount > LIMITS.maxMoney) return { ok: false, error: 'Bill total is too large' };
    const totalPayableAmount = Math.round(before);                  // nearest rupee, as the website
    if (!(totalPayableAmount > 0)) return { ok: false, error: 'Bill total must be more than 0' };
    const roundOff = r2(totalPayableAmount - before);

    const paidAmount = r2(Math.max(0, num(input.paidAmount)));
    const dueAdvance = r2(paidAmount - totalPayableAmount);         // negative = due, positive = advance

    const tdsApplicable = totalPayableAmount > TDS_THRESHOLD;
    return {
        ok: true,
        rule: legacy ? RULE_LEGACY : RULE,
        discountMode: legacy ? 'after_gst' : 'before_gst',
        goldRate: gold, silverRate: silver,
        items: lines,
        itemsTotal: r2(itemsTotal),
        totalAmount, additionalCharges, additionalTaxable: addTaxable, additionalGst: r2(addCg + addSg + addIg),
        discount: legacy ? discountAsked : 0,                       // the website's own field: only the old rule uses it
        discountGiven: legacy ? discountAsked : r2(bill0 - totalPayableAmount),   // what the customer actually saves
        discountBeforeGst,                                          // the part taken off the taxable value
        billBeforeDiscount: bill0,
        grossTaxable,                                               // goods value before the discount
        metalValue, hallmarkTotal, maxDiscount,
        roundOff,
        totalPayableAmount,
        paidAmount, dueAdvance,
        dueAmount: dueAdvance < 0 ? r2(-dueAdvance) : 0,
        advanceAmount: dueAdvance > 0 ? dueAdvance : 0,
        tdsApplicable,
        tdsRate: tdsApplicable ? TDS_RATE : 0,
        tdsAmount: tdsApplicable ? r2(totalPayableAmount * TDS_RATE / 100) : 0,
        gstSummary: {
            total_taxable_amount: r2(sumTaxable),
            total_cgst: r2(sumCgst),
            total_sgst: r2(sumSgst),
            total_gst: r2(sumCgst + sumSgst + sumIgst),
            cgst_rate: interstate ? 0 : 1.5,
            sgst_rate: interstate ? 0 : 1.5,
            ...(interstate ? { total_igst: r2(sumIgst), igst_rate: 3 } : {}),
        },
        gstType: interstate ? 'IGST' : 'CGST_SGST',
    };
}

// ── Amount in words (Indian numbering: thousand / lakh / crore) ──────────────
const EN_UNITS = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve',
    'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const EN_TENS = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
const enBelow100 = (n) => (n < 20 ? EN_UNITS[n] : EN_TENS[Math.floor(n / 10)] + (n % 10 ? ' ' + EN_UNITS[n % 10] : ''));

function enWords(n) {
    if (n === 0) return 'Zero';
    const parts = [];
    const crore = Math.floor(n / 1e7); n %= 1e7;
    const lakh = Math.floor(n / 1e5); n %= 1e5;
    const thousand = Math.floor(n / 1e3); n %= 1e3;
    const hundred = Math.floor(n / 100); n %= 100;
    if (crore) parts.push(enWords(crore) + ' Crore');
    if (lakh) parts.push(enBelow100(lakh) + ' Lakh');
    if (thousand) parts.push(enBelow100(thousand) + ' Thousand');
    if (hundred) parts.push(EN_UNITS[hundred] + ' Hundred');
    if (n) parts.push((parts.length ? 'and ' : '') + enBelow100(n));
    return parts.join(' ');
}

// Bengali has an irregular word for every number from 1 to 99.
const BN_0_99 = ('শূন্য এক দুই তিন চার পাঁচ ছয় সাত আট নয় দশ এগারো বারো তেরো চৌদ্দ পনেরো ষোলো সতেরো আঠারো উনিশ ' +
    'বিশ একুশ বাইশ তেইশ চব্বিশ পঁচিশ ছাব্বিশ সাতাশ আঠাশ ঊনত্রিশ ত্রিশ একত্রিশ বত্রিশ তেত্রিশ চৌত্রিশ পঁয়ত্রিশ ছত্রিশ সাঁইত্রিশ আটত্রিশ ঊনচল্লিশ ' +
    'চল্লিশ একচল্লিশ বিয়াল্লিশ তেতাল্লিশ চুয়াল্লিশ পঁয়তাল্লিশ ছেচল্লিশ সাতচল্লিশ আটচল্লিশ ঊনপঞ্চাশ ' +
    'পঞ্চাশ একান্ন বাহান্ন তিপ্পান্ন চুয়ান্ন পঞ্চান্ন ছাপ্পান্ন সাতান্ন আটান্ন ঊনষাট ' +
    'ষাট একষট্টি বাষট্টি তেষট্টি চৌষট্টি পঁয়ষট্টি ছেষট্টি সাতষট্টি আটষট্টি ঊনসত্তর ' +
    'সত্তর একাত্তর বাহাত্তর তিয়াত্তর চুয়াত্তর পঁচাত্তর ছিয়াত্তর সাতাত্তর আটাত্তর ঊনআশি ' +
    'আশি একাশি বিরাশি তিরাশি চুরাশি পঁচাশি ছিয়াশি সাতাশি আটাশি ঊননব্বই ' +
    'নব্বই একানব্বই বিরানব্বই তিরানব্বই চুরানব্বই পঁচানব্বই ছিয়ানব্বই সাতানব্বই আটানব্বই নিরানব্বই').split(' ');

function bnWords(n) {
    if (n === 0) return BN_0_99[0];
    const parts = [];
    const crore = Math.floor(n / 1e7); n %= 1e7;
    const lakh = Math.floor(n / 1e5); n %= 1e5;
    const thousand = Math.floor(n / 1e3); n %= 1e3;
    const hundred = Math.floor(n / 100); n %= 100;
    if (crore) parts.push(bnWords(crore) + ' কোটি');
    if (lakh) parts.push(BN_0_99[lakh] + ' লক্ষ');
    if (thousand) parts.push(BN_0_99[thousand] + ' হাজার');
    if (hundred) parts.push(BN_0_99[hundred] + ' শত');
    if (n) parts.push(BN_0_99[n]);
    return parts.join(' ');
}

/** "Eight Hundred Rupees Only (আটশ ... টাকা মাত্র)" — the "English (Bengali)" shape stored on invoices. */
function amountInWords(amount) {
    const a = Math.max(0, r2(amount));
    const rupees = Math.floor(a);
    const paise = Math.round((a - rupees) * 100);
    let en = `${enWords(rupees)} Rupees`;
    let bn = `${bnWords(rupees)} টাকা`;
    if (paise) {
        en += ` and ${enBelow100(paise)} Paise`;
        bn += ` ${BN_0_99[paise]} পয়সা`;
    }
    en += ' Only';
    bn += ' মাত্র';
    return { en, bn, combined: `${en} (${bn})` };
}

/**
 * Same rule as the website: delivered + fully paid = delivered; not yet
 * delivered = pending; delivered but unpaid = active. Dates are plain
 * YYYY-MM-DD strings (India calendar days), compared as text.
 */
function invoiceStatus(totalPayable, paid, deliveryYmd, todayYmd) {
    const fullyPaid = Math.abs(num(totalPayable) - num(paid)) < 0.01;
    const delivered = !!deliveryYmd && String(deliveryYmd) <= String(todayYmd);
    if (fullyPaid && delivered) return 'delivered';
    if (!delivered) return 'pending';
    return 'active';
}

/** Today's date in India (YYYY-MM-DD), whatever timezone the server runs in. */
function todayIST(now = new Date()) {
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

module.exports = { composeParticulars, RULE, RULE_LEGACY, METALS, DEFAULT_HSN, TDS_THRESHOLD, LIMITS, computeInvoice, amountInWords, invoiceStatus, todayIST, r2, r3, metalOf };
