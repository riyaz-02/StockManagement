/**
 * stockSummary.js — the metal balance ("Summary" / discrepancy) as pure functions. See docs/STOCK_SUMMARY.md.
 *
 * Per metal, in whole MILLIGRAMS (integers, so nothing drifts), from numbers the server read out of the shop's records:
 *   Receipts = purchases x (1 + allowance%) + old metal taken in + raw metal bought
 *   Stock    = pieces in the shop + pieces out (repair / agent / customer) + bulk stock
 *   Out      = sold on bills (net of returned pieces put back) + approved wastage
 *   Variance = Receipts - (Stock + Out)     > 0: metal not accounted for     < 0: more than the records explain
 * Nothing here touches the database or a client's numbers.
 */
'use strict';

const METALS = ['gold', 'silver'];

const DEFAULT_SETTINGS = {
    goldAllowancePct: 10,      // weight gained when 99.5 bullion is alloyed into jewellery (the old website's +10 %)
    silverAllowancePct: 20,    // (the old website's +20 %)
    okPct: 1.5,                // below this share of the metal received the difference is normal
    highPct: 5,                // from this share it is high
    minAlertGrams: 1,          // a difference this small is never an alert
};
const SETTING_LIMITS = {
    goldAllowancePct: [0, 100], silverAllowancePct: [0, 100], okPct: [0, 50], highPct: [0.1, 100], minAlertGrams: [0, 1000],
};

const toMg = (g) => { const n = Number(g); return Number.isFinite(n) ? Math.round(n * 1000) : 0; };
const fromMg = (mg) => Math.round(mg) / 1000 + 0;   // + 0 turns -0 into 0
const pct2 = (n) => Math.round(n * 100) / 100;

/** A stored settings document merged over the defaults; anything out of range falls back to the default. */
function resolveSettings(stored) {
    const out = { ...DEFAULT_SETTINGS };
    const src = stored && stored.reconcile ? stored.reconcile : {};
    for (const [k, [lo, hi]] of Object.entries(SETTING_LIMITS)) {
        const n = Number(src[k]);
        if (src[k] !== undefined && src[k] !== '' && Number.isFinite(n) && n >= lo && n <= hi) out[k] = n;
    }
    if (out.highPct <= out.okPct) { out.okPct = DEFAULT_SETTINGS.okPct; out.highPct = DEFAULT_SETTINGS.highPct; }
    return out;
}

/** A partial update ({ goldAllowancePct: 10, ... }) checked against the limits: { set } or { error }. */
function validateSettings(body) {
    const set = {};
    for (const [k, v] of Object.entries(body || {})) {
        const lim = SETTING_LIMITS[k];
        if (!lim) return { error: `Unknown setting reconcile.${k}` };
        const n = Number(v);
        if (v === '' || v === null || !Number.isFinite(n) || n < lim[0] || n > lim[1]) return { error: `reconcile.${k} must be a number from ${lim[0]} to ${lim[1]}` };
        set[`reconcile.${k}`] = Math.round(n * 100) / 100;
    }
    return { set };
}

/** normal | moderate | high for a variance (grams) and its share (%) of the metal received. */
function severityOf(varianceG, pct, s = DEFAULT_SETTINGS) {
    if (Math.abs(varianceG) <= s.minAlertGrams) return 'normal';
    const p = Math.abs(pct);
    if (p < s.okPct) return 'normal';
    if (p < s.highPct) return 'moderate';
    return 'high';
}

/**
 * The balance of one metal. `i` (grams, all optional): purchased, oldMetal, rawMetal, inShop, withOthers, bulk, sold, returned,
 * wastage (approved only). Returns grams (3 decimals) with the severity and the direction of the difference.
 */
function calcMetal(metal, i = {}, settings = DEFAULT_SETTINGS) {
    const allowancePct = metal === 'silver' ? settings.silverAllowancePct : settings.goldAllowancePct;
    const purchased = toMg(i.purchased);
    const allowance = Math.round((purchased * allowancePct) / 100);
    const adjusted = purchased + allowance;
    const oldMetal = toMg(i.oldMetal);
    const rawMetal = toMg(i.rawMetal);
    const receipts = adjusted + oldMetal + rawMetal;

    const inShop = toMg(i.inShop);
    const withOthers = toMg(i.withOthers);
    const bulk = toMg(i.bulk);
    const stock = inShop + withOthers + bulk;

    const soldGross = toMg(i.sold);
    const returned = toMg(i.returned);
    const soldNet = Math.max(0, soldGross - returned);
    const wastage = toMg(i.wastage);
    const out = soldNet + wastage;

    const expectedOut = receipts - stock;            // what must have left the shop (the old "expected issuance")
    const variance = receipts - (stock + out);
    const pct = receipts > 0 ? pct2((variance / receipts) * 100) : 0;
    const severity = severityOf(fromMg(variance), pct, settings);
    const direction = severity === 'normal' && Math.abs(fromMg(variance)) <= settings.minAlertGrams ? 'balanced' : variance > 0 ? 'short' : variance < 0 ? 'excess' : 'balanced';
    return {
        metal,
        receipts: {
            purchased: fromMg(purchased), allowancePct, allowance: fromMg(allowance), adjustedPurchase: fromMg(adjusted),
            oldMetal: fromMg(oldMetal), rawMetal: fromMg(rawMetal), total: fromMg(receipts),
        },
        stock: { inShop: fromMg(inShop), withOthers: fromMg(withOthers), bulk: fromMg(bulk), total: fromMg(stock) },
        out: { soldGross: fromMg(soldGross), returned: fromMg(returned), sold: fromMg(soldNet), wastage: fromMg(wastage), total: fromMg(out) },
        expectedOut: fromMg(expectedOut),
        variance: fromMg(variance),
        variancePct: pct,
        severity,
        direction,
        returnsExceedSales: returned > soldGross,
    };
}

// ── data checks and insights (every finding in English and Bengali) ────────────────────────────────────────────

const t = (en, bn) => ({ en, bn });
const g3 = (n) => (Math.round(Number(n || 0) * 1000) / 1000).toFixed(3);
const MN = { gold: { en: 'gold', bn: 'স্বর্ণ' }, silver: { en: 'silver', bn: 'রূপা' } };

/**
 * ctx: { gold:{...}, silver:{...} } of counts/weights the data layer found, plus { tallyDaysAgo, branchOnly }.
 * per metal: removedPieces, removedG, actionNeededPieces, actionNeededG, zeroWeightPieces, linesNoWeight, linesOtherMetal,
 *   purchasesBad, cancelledPendingPieces, cancelledPendingG, soldNoBillPieces, pendingWastageCount, pendingWastageG, bulkEntries, unknownStatusPieces
 */
function buildChecks(ctx = {}) {
    const out = [];
    const add = (id, level, count, grams, en, bn, scope) => out.push({ id, level, count, grams: grams == null ? null : Math.round(grams * 1000) / 1000, scope: scope || null, en, bn });
    const sum = (k) => METALS.reduce((a, m) => a + Number((ctx[m] || {})[k] || 0), 0);
    const each = (k, fn) => METALS.forEach((m) => { const v = Number((ctx[m] || {})[k] || 0); if (v > 0) fn(m, v, ctx[m]); });

    if (ctx.branchOnly) add('branch_view', 'info', 0, null, 'This is your branch only. Approved wastage and the other branches are not included, so the difference is not the whole shop.', 'এটি শুধু আপনার শাখার হিসাব। অনুমোদিত ক্ষতি ও অন্য শাখা ধরা হয়নি, তাই এটি পুরো দোকানের গড়মিল নয়।');
    each('cancelledPendingPieces', (m, n, c) => add('cancelled_not_restored', 'error', n, c.cancelledPendingG, `${n} ${MN[m].en} piece(s) of cancelled bills are still marked sold (${g3(c.cancelledPendingG)} g). Put them back into stock: until then the ${MN[m].en} difference is overstated.`, `বাতিল বিলের ${n}টি ${MN[m].bn} পিস এখনও বিক্রিত দেখাচ্ছে (${g3(c.cancelledPendingG)} গ্রাম)। এগুলো স্টকে ফিরিয়ে আনুন, না হলে ${MN[m].bn} গড়মিল বেশি দেখাবে।`, m));
    METALS.forEach((m) => { if ((ctx[m] || {}).returnsExceedSales) add('returns_exceed_sales', 'error', 1, null, `Returned ${MN[m].en} is more than the ${MN[m].en} sold: a return was recorded twice or on the wrong bill.`, `ফেরত ${MN[m].bn} বিক্রির চেয়ে বেশি: কোনো ফেরত দুইবার বা ভুল বিলে লেখা হয়েছে।`, m); });
    each('linesNoWeight', (m, n) => add('bill_lines_no_weight', 'warn', n, null, `${n} ${MN[m].en} bill line(s) have no weight, so they are not counted as sold. Open those bills and enter the net weight.`, `${n}টি ${MN[m].bn} বিল লাইনে ওজন নেই, তাই বিক্রি হিসাবে ধরা হয়নি। বিলগুলো খুলে নিট ওজন লিখুন।`, m));
    const otherLines = Number(ctx.linesOtherMetal || 0);
    if (otherLines > 0) add('bill_lines_other_metal', 'info', otherLines, null, `${otherLines} bill line(s) are for a metal other than gold or silver (or have no metal). They are not part of this check.`, `${otherLines}টি বিল লাইন স্বর্ণ বা রূপা ছাড়া অন্য ধাতুর (বা ধাতু লেখা নেই)। এগুলো এই হিসাবে ধরা হয়নি।`);
    each('purchasesBad', (m, n) => add('purchases_no_weight', 'warn', n, null, `${n} ${MN[m].en} purchase(s) have no weight, so they add nothing to the metal received. Correct them.`, `${n}টি ${MN[m].bn} ক্রয়ে ওজন নেই, তাই প্রাপ্ত ধাতুতে যোগ হয়নি। ঠিক করুন।`, m));
    each('zeroWeightPieces', (m, n) => add('pieces_zero_weight', 'warn', n, null, `${n} ${MN[m].en} piece(s) in stock have no net weight. They add nothing to the stock.`, `স্টকের ${n}টি ${MN[m].bn} পিসের নিট ওজন নেই। স্টকে কিছু যোগ হচ্ছে না।`, m));
    const unknown = sum('unknownStatusPieces');
    if (unknown > 0) add('pieces_unknown_status', 'warn', unknown, null, `${unknown} piece(s) have a status this check does not know, so they are not counted anywhere.`, `${unknown}টি পিসের অবস্থা অজানা, তাই কোথাও ধরা হয়নি।`);
    each('soldNoBillPieces', (m, n) => add('sold_without_bill', 'warn', n, null, `${n} ${MN[m].en} piece(s) are marked sold but no bill is linked. Their weight is neither in stock nor in sales.`, `${n}টি ${MN[m].bn} পিস বিক্রিত কিন্তু কোনো বিল যুক্ত নেই। ওজনটি স্টক বা বিক্রি কোথাও নেই।`, m));
    if (Number(ctx.duplicateBills || 0) > 0) add('duplicate_bill_numbers', 'warn', Number(ctx.duplicateBills), null, `${ctx.duplicateBills} bill number(s) are used more than once: the same sale may be counted twice.`, `${ctx.duplicateBills}টি বিল নম্বর একাধিকবার আছে: একই বিক্রি দুবার ধরা হতে পারে।`);
    each('pendingWastageCount', (m, n, c) => add('wastage_pending', 'info', n, c.pendingWastageG, `${n} ${MN[m].en} wastage report(s) (${g3(c.pendingWastageG)} g) are waiting for approval and are not counted yet.`, `${n}টি ${MN[m].bn} ক্ষতির রিপোর্ট (${g3(c.pendingWastageG)} গ্রাম) অনুমোদনের অপেক্ষায়, এখনও ধরা হয়নি।`, m));
    each('actionNeededPieces', (m, n, c) => add('pieces_need_details', 'info', n, c.actionNeededG, `${n} ${MN[m].en} piece(s) (${g3(c.actionNeededG)} g) were added quickly and still need details. They are counted as stock.`, `${n}টি ${MN[m].bn} পিস (${g3(c.actionNeededG)} গ্রাম) তাড়াতাড়ি যোগ করা, বিবরণ বাকি। স্টকে ধরা আছে।`, m));
    each('removedPieces', (m, n, c) => add('pieces_removed', 'info', n, c.removedG, `${n} ${MN[m].en} piece(s) (${g3(c.removedG)} g) were removed from the stock list. They are not counted as stock: if they were not sold, they are part of the difference.`, `${n}টি ${MN[m].bn} পিস (${g3(c.removedG)} গ্রাম) স্টক তালিকা থেকে সরানো হয়েছে। স্টকে ধরা নেই: বিক্রি না হয়ে থাকলে এগুলো গড়মিলের অংশ।`, m));
    const bulkTotal = sum('bulkEntries');
    if (bulkTotal === 0) add('no_bulk_stock', 'info', 0, null, 'No bulk stock is entered. Dust, parts, raw and in-process metal kept without a barcode must be entered as Bulk stock, or they show up as a difference.', 'কোনো বাল্ক স্টক লেখা নেই। বারকোড ছাড়া রাখা ধুলো, অংশ, কাঁচা বা তৈরির মাঝের ধাতু বাল্ক স্টক হিসেবে লিখুন, না হলে গড়মিল দেখাবে।');
    if (ctx.tallyDaysAgo === null || ctx.tallyDaysAgo === undefined) add('tally_never', 'warn', 0, null, 'No stock tally has been completed. Count the shop against the system so the stock can be trusted.', 'এখনও কোনো স্টক ট্যালি সম্পূর্ণ হয়নি। দোকানের মাল গুনে সিস্টেমের সঙ্গে মিলিয়ে নিন।');
    else if (ctx.tallyDaysAgo > 45) add('tally_old', 'warn', ctx.tallyDaysAgo, null, `The last stock tally was ${ctx.tallyDaysAgo} days ago. Count the shop again.`, `শেষ স্টক ট্যালি ${ctx.tallyDaysAgo} দিন আগে। আবার গুনে দেখুন।`);
    if (ctx.tallyRunning) add('tally_running', 'info', ctx.tallyRunning.checked, null, `A stock tally is in progress (${ctx.tallyRunning.checked} of ${ctx.tallyRunning.total} pieces checked). Finish it to confirm the stock.`, `একটি স্টক ট্যালি চলছে (${ctx.tallyRunning.total}টির মধ্যে ${ctx.tallyRunning.checked}টি মিলানো হয়েছে)। স্টক নিশ্চিত করতে শেষ করুন।`);
    const rank = { error: 0, warn: 1, info: 2 };
    return out.sort((a, b) => rank[a.level] - rank[b.level]);
}

/** reliable when no error or warning is open; check when there is something to fix first. */
function confidenceOf(checks) {
    const errors = checks.filter((c) => c.level === 'error').length;
    const warns = checks.filter((c) => c.level === 'warn').length;
    return {
        level: errors ? 'fix' : warns ? 'check' : 'reliable',
        errors, warnings: warns,
        en: errors ? 'Fix the red items first: the difference is not reliable yet.' : warns ? 'Look at the yellow items: they can change the difference.' : 'No data problems found: the difference can be trusted.',
        bn: errors ? 'আগে লাল চিহ্নিত বিষয়গুলো ঠিক করুন: গড়মিল এখনও নির্ভরযোগ্য নয়।' : warns ? 'হলুদ বিষয়গুলো দেখুন: এগুলো গড়মিল বদলে দিতে পারে।' : 'কোনো তথ্যের সমস্যা নেই: গড়মিল ভরসাযোগ্য।',
    };
}

/** What the number means and what to do about it, from the actual findings. */
function buildInsights(metal, calc, c = {}, settings = DEFAULT_SETTINGS) {
    const n = MN[metal];
    const analysis = [];
    const todo = [];
    const v = calc.variance;
    const av = Math.abs(v);
    const head = (en, bn) => ({ en, bn });
    let headline;
    if (calc.direction === 'balanced' || calc.severity === 'normal') {
        headline = head(`${n.en[0].toUpperCase()}${n.en.slice(1)}: balanced (${g3(v)} g, ${Math.abs(calc.variancePct)}% of the metal received).`, `${n.bn}: মিলেছে (${g3(v)} গ্রাম, প্রাপ্ত ধাতুর ${Math.abs(calc.variancePct)}%)।`);
        analysis.push(t(`The difference is within the normal range (below ${settings.okPct}% of the metal received).`, `গড়মিল স্বাভাবিক সীমার মধ্যে (প্রাপ্ত ধাতুর ${settings.okPct}% এর কম)।`));
        analysis.push(t('Small differences come from weighing, filing loss in making and old entries.', 'ছোট গড়মিল ওজনের তারতম্য, কাজের সময় ক্ষতি ও পুরনো এন্ট্রি থেকে আসে।'));
        todo.push(t('Keep entering purchases, bills, wastage and bulk stock as they happen.', 'ক্রয়, বিল, ক্ষতি ও বাল্ক স্টক ঘটার সঙ্গে সঙ্গে লিখতে থাকুন।'));
        todo.push(t('Run a stock tally every month or two.', 'প্রতি এক-দুই মাসে একবার স্টক ট্যালি করুন।'));
    } else if (v > 0) {
        headline = head(`${n.en[0].toUpperCase()}${n.en.slice(1)}: ${g3(av)} g (${Math.abs(calc.variancePct)}%) of the metal received is not accounted for.`, `${n.bn}: প্রাপ্ত ধাতুর ${g3(av)} গ্রাম (${Math.abs(calc.variancePct)}%) এর হিসাব মিলছে না।`);
        analysis.push(t(`More ${n.en} came in than the stock, the bills and the approved wastage explain (${calc.severity === 'high' ? 'high' : 'moderate'}: ${Math.abs(calc.variancePct)}% of the metal received).`, `স্টক, বিল ও অনুমোদিত ক্ষতি মিলিয়েও ${n.bn} ${g3(av)} গ্রাম কম পড়ছে।`));
        if (c.removedG > 0) analysis.push(t(`Pieces removed from the stock list weigh ${g3(c.removedG)} g${c.removedG >= av * 0.5 ? ': that could explain much of the gap if they were not sold' : ''}.`, `স্টক তালিকা থেকে সরানো পিসের ওজন ${g3(c.removedG)} গ্রাম${c.removedG >= av * 0.5 ? ': বিক্রি না হয়ে থাকলে এটি গড়মিলের বড় অংশ হতে পারে' : ''}।`));
        if (c.pendingWastageG > 0) analysis.push(t(`${g3(c.pendingWastageG)} g of wastage is waiting for approval: approving it would reduce the gap.`, `${g3(c.pendingWastageG)} গ্রাম ক্ষতি অনুমোদনের অপেক্ষায়: অনুমোদন হলে গড়মিল কমবে।`));
        if (!c.bulkEntries) analysis.push(t('No bulk stock is entered. Dust, parts and in-process metal not on a barcode are probably part of the gap.', 'বাল্ক স্টক লেখা নেই। বারকোডহীন ধুলো, অংশ ও তৈরির মাঝের ধাতু সম্ভবত গড়মিলের অংশ।'));
        if (c.actionNeededPieces > 0) analysis.push(t(`${c.actionNeededPieces} piece(s) still need details; check their weights.`, `${c.actionNeededPieces}টি পিসের বিবরণ বাকি; ওজন যাচাই করুন।`));
        todo.push(t('Enter all loose metal (dust, parts, raw, in-process) as Bulk stock.', 'সব খোলা ধাতু (ধুলো, অংশ, কাঁচা, তৈরির মাঝের) বাল্ক স্টক হিসেবে লিখুন।'));
        if (c.removedG > 0) todo.push(t('Open the removed pieces and confirm each one was sold or put it back.', 'সরানো পিসগুলো খুলে দেখুন প্রতিটি বিক্রি হয়েছে কি না, না হলে ফিরিয়ে আনুন।'));
        if (c.pendingWastageG > 0) todo.push(t('Review and approve the pending wastage reports.', 'অপেক্ষমাণ ক্ষতির রিপোর্টগুলো দেখে অনুমোদন করুন।'));
        todo.push(t('Run a stock tally to find pieces that are missing from the shop.', 'দোকানে নেই এমন পিস খুঁজতে স্টক ট্যালি করুন।'));
        todo.push(t('Check the karigars: metal given to them must be returned as pieces, bulk stock or wastage.', 'কারিগরদের মাল দেখুন: তাদের দেওয়া ধাতু পিস, বাল্ক বা ক্ষতি হিসেবে ফেরত আসা চাই।'));
        if (calc.severity === 'high') todo.push(t('Compare the last six months of purchases and GST bills line by line.', 'গত ছয় মাসের ক্রয় ও জিএসটি বিল লাইন ধরে মিলিয়ে দেখুন।'));
        if (metal === 'silver' && calc.severity === 'high') todo.push(t('Check silver fabrication loss and ask an outside accountant to audit if it stays high.', 'রূপার ফ্যাব্রিকেশন লস দেখুন; বেশি থাকলে বাইরের হিসাবরক্ষক দিয়ে অডিট করান।'));
    } else {
        headline = head(`${n.en[0].toUpperCase()}${n.en.slice(1)}: ${g3(av)} g (${Math.abs(calc.variancePct)}%) more than the records explain.`, `${n.bn}: রেকর্ডের চেয়ে ${g3(av)} গ্রাম (${Math.abs(calc.variancePct)}%) বেশি।`);
        analysis.push(t(`Stock plus sales plus wastage is more ${n.en} than was received: a purchase or old metal may not be recorded, or something is entered twice.`, `স্টক, বিক্রি ও ক্ষতি মিলিয়ে প্রাপ্ত ${n.bn} এর চেয়ে বেশি: কোনো ক্রয় বা পুরনো ধাতু লেখা হয়নি, বা কিছু দুবার লেখা হয়েছে।`));
        if (calc.receipts.allowancePct > 0) analysis.push(t(`The allowance for alloy and process is ${calc.receipts.allowancePct}%. If it is too low for your work, adjust it in Stock settings.`, `খাদ ও কাজের জন্য ধরা বাড়তি ${calc.receipts.allowancePct}%। আপনার কাজের জন্য কম হলে স্টক সেটিংসে বদলান।`));
        todo.push(t('Check that every purchase bill and every old / raw metal receipt is entered.', 'প্রতিটি ক্রয় বিল এবং পুরনো/কাঁচা ধাতু প্রাপ্তি লেখা আছে কি না দেখুন।'));
        todo.push(t('Look for a piece or a bulk entry that was entered twice.', 'দুবার লেখা কোনো পিস বা বাল্ক এন্ট্রি আছে কি না খুঁজুন।'));
    }
    if (calc.returnsExceedSales) analysis.push(t('Returns are larger than sales: see the data checks.', 'ফেরত বিক্রির চেয়ে বেশি: তথ্য যাচাই দেখুন।'));
    return { metal, severity: calc.severity, headline, analysis, recommendations: todo };
}

// ── snapshots (the website's `daily_snapshots` shape, plus what the app adds) ─────────────────────────────────

/** One metal of a snapshot document: the website's field names first, the app's extras beside them. */
function snapshotMetal(calc, extra = {}) {
    const r = calc.receipts, s = calc.stock, o = calc.out;
    return {
        purchase_total: r.purchased,
        calculated_purchase: r.adjustedPurchase,
        stock_total: s.total,
        expected_stock_debit: calc.expectedOut,
        total_sold: o.sold,
        final_result: calc.variance,
        discrepancy_percentage: calc.variancePct,
        // the app's own fields
        wastage_total: o.wastage, old_metal_total: r.oldMetal, raw_metal_total: r.rawMetal, receipts_total: r.total,
        in_shop: s.inShop, with_others: s.withOthers, bulk_total: s.bulk, returned_total: o.returned,
        allowance_pct: r.allowancePct, severity: calc.severity,
        ...extra,
    };
}

/** A snapshot's metal (old website or new) as a uniform record. The old site had no wastage field: it follows from its own formula. */
function normalizeSnapshotMetal(m = {}) {
    const adjusted = Number(m.calculated_purchase || 0);
    const oldMetal = Number(m.old_metal_total || 0), rawMetal = Number(m.raw_metal_total || 0);
    const sold = Number(m.total_sold || 0);
    const expected = Number(m.expected_stock_debit != null ? m.expected_stock_debit : adjusted - Number(m.stock_total || 0));
    const variance = Number(m.final_result || 0);
    const wastage = m.wastage_total != null ? Number(m.wastage_total) : Math.max(0, Math.round((expected - sold - variance) * 1000) / 1000);
    const receipts = m.receipts_total != null ? Number(m.receipts_total) : adjusted + oldMetal + rawMetal;
    const pct = m.discrepancy_percentage != null ? Number(m.discrepancy_percentage) : (receipts > 0 ? pct2((variance / receipts) * 100) : 0);
    return { stock: Number(m.stock_total || 0), receipts, sold, wastage, out: Math.round((sold + wastage) * 1000) / 1000, variance, variancePct: pct2(pct), severity: m.severity || null };
}

const ymd = (d) => String(d || '').slice(0, 10);
function weekKey(date) {
    const d = new Date(`${ymd(date)}T00:00:00Z`);
    const day = (d.getUTCDay() + 6) % 7;              // Monday = 0
    d.setUTCDate(d.getUTCDate() - day + 3);          // the Thursday of this ISO week
    const first = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
    const week = 1 + Math.round(((d - first) / 86400000 - 3 + ((first.getUTCDay() + 6) % 7)) / 7);
    return `${d.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * History rows from snapshots. Balances of a period = its LAST snapshot; in / out = the change of the running totals
 * between that snapshot and the one before the period (the first snapshot has no earlier one: in / out are null).
 * view: daily | weekly | monthly. Newest first.
 */
function rollup(snapshots, view = 'daily', settings = DEFAULT_SETTINGS) {
    const sorted = [...snapshots].filter((s) => ymd(s.date)).sort((a, b) => ymd(a.date).localeCompare(ymd(b.date)));
    const keyOf = (d) => (view === 'weekly' ? weekKey(d) : view === 'monthly' ? ymd(d).slice(0, 7) : ymd(d));
    const labelOf = (key, date) => (view === 'weekly' ? `Week ${key.slice(6)}, ${key.slice(0, 4)}` : view === 'monthly' ? `${MONTHS[Number(key.slice(5, 7)) - 1]} ${key.slice(0, 4)}` : date);
    const groups = [];
    for (const s of sorted) {
        const k = keyOf(s.date);
        const last = groups[groups.length - 1];
        if (last && last.key === k) { last.snap = s; last.count += 1; } else groups.push({ key: k, snap: s, count: 1, firstDate: ymd(s.date) });
    }
    let prev = null;
    const rows = groups.map((g) => {
        const date = ymd(g.snap.date);
        const row = { key: g.key, label: labelOf(g.key, date), date, from: g.firstDate, snapshots: g.count, basis: g.snap.basis || 'ledger' };
        for (const m of METALS) {
            const cur = normalizeSnapshotMetal(g.snap[m]);
            const before = prev ? normalizeSnapshotMetal(prev.snap[m]) : null;
            const r3 = (n) => Math.round(n * 1000) / 1000;
            row[m] = {
                stock: cur.stock, in: before ? r3(cur.receipts - before.receipts) : null, out: before ? r3(cur.out - before.out) : null,
                variance: cur.variance, variancePct: cur.variancePct, severity: cur.severity || severityOf(cur.variance, cur.variancePct, settings),
                sold: cur.sold, wastage: cur.wastage, receipts: cur.receipts,
            };
        }
        row.methodChange = !!prev && (prev.snap.basis || 'ledger') !== (g.snap.basis || 'ledger');
        prev = g;
        return row;
    });
    return rows.reverse();
}

/** Start to end of a history range: how stock and the difference moved, and whether the two ends are comparable. */
function trend(rows) {
    if (!rows || rows.length < 2) return { enough: false };
    const first = rows[rows.length - 1], last = rows[0];
    const out = { enough: true, from: first.date, to: last.date, comparable: first.basis === last.basis && !rows.slice(0, -1).some((r) => r.methodChange) };
    for (const m of METALS) {
        const dv = Math.round((last[m].variance - first[m].variance) * 1000) / 1000;
        out[m] = {
            stockStart: first[m].stock, stockEnd: last[m].stock, stockChange: Math.round((last[m].stock - first[m].stock) * 1000) / 1000,
            varianceStart: first[m].variance, varianceEnd: last[m].variance, varianceChange: dv,
            improving: Math.abs(last[m].variance) < Math.abs(first[m].variance),
        };
    }
    return out;
}

module.exports = {
    METALS, DEFAULT_SETTINGS, SETTING_LIMITS, resolveSettings, validateSettings, toMg, fromMg, severityOf,
    calcMetal, buildChecks, confidenceOf, buildInsights, snapshotMetal, normalizeSnapshotMetal, rollup, trend, weekKey,
};
