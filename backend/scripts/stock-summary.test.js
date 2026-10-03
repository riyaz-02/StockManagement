'use strict';
/** The metal balance engine (services/stockSummary.js): pure functions, exact numbers. node scripts/stock-summary.test.js */
const assert = require('assert');
const S = require('../services/stockSummary');
let n = 0;
const ok = (m) => { n += 1; console.log(`ok - ${m}`); };

// ── the balance ──
let c = S.calcMetal('gold', { purchased: 100, oldMetal: 10, rawMetal: 5, inShop: 60, withOthers: 5, bulk: 30, sold: 12, returned: 2, wastage: 1.5 });
assert.strictEqual(c.receipts.adjustedPurchase, 110);
assert.strictEqual(c.receipts.allowance, 10);
assert.strictEqual(c.receipts.total, 125);
assert.strictEqual(c.stock.total, 95);
assert.strictEqual(c.out.sold, 10, 'sold is net of returned pieces put back');
assert.strictEqual(c.out.total, 11.5);
assert.strictEqual(c.expectedOut, 30);                 // 125 - 95
assert.strictEqual(c.variance, 18.5);                  // 125 - (95 + 11.5)
assert.strictEqual(c.variancePct, 14.8);
assert.strictEqual(c.severity, 'high');
assert.strictEqual(c.direction, 'short');
ok('gold balance: receipts, stock, sold net of returns, wastage and the variance');

c = S.calcMetal('silver', { purchased: 1000 });
assert.strictEqual(c.receipts.adjustedPurchase, 1200, 'silver allowance is 20 %');
assert.strictEqual(S.calcMetal('gold', { purchased: 1000 }).receipts.adjustedPurchase, 1100, 'gold allowance is 10 %');
ok('the allowance follows the metal and the settings');
c = S.calcMetal('gold', { purchased: 1000 }, S.resolveSettings({ reconcile: { goldAllowancePct: 8.5 } }));
assert.strictEqual(c.receipts.adjustedPurchase, 1085);
ok('a changed allowance setting changes the balance');

// exactness: float noise never reaches the answer
c = S.calcMetal('gold', { purchased: 0.1 + 0.2, inShop: 0.30000000000000004 / 1.1 });
assert.strictEqual(c.receipts.purchased, 0.3);
assert.strictEqual(typeof c.variance, 'number');
c = S.calcMetal('gold', { purchased: 2326.91, inShop: 1405.34, bulk: 0, sold: 809.988, wastage: 3.49 });
assert.strictEqual(c.receipts.adjustedPurchase, 2559.601);
assert.strictEqual(c.variance, 340.783);                // the real production figure
ok('whole-milligram arithmetic reproduces the real production difference exactly (340.783 g)');

// ── direction and severity ──
c = S.calcMetal('gold', { purchased: 100, inShop: 100, sold: 10 });          // receipts 110 vs 110 accounted
assert.strictEqual(c.variance, 0);
assert.strictEqual(c.direction, 'balanced');
c = S.calcMetal('gold', { purchased: 100, inShop: 100, sold: 12 });          // 2 g more than received
assert.strictEqual(c.variance, -2);
assert.strictEqual(c.direction, 'excess');
assert.strictEqual(c.severity, 'moderate');                                  // 1.8 % of 110
ok('a negative variance is an excess (more than the records explain)');
assert.strictEqual(S.severityOf(0.9, 40), 'normal', 'a variance of 1 g or less is never an alert');
assert.strictEqual(S.severityOf(10, 1.49), 'normal');
assert.strictEqual(S.severityOf(10, 1.5), 'moderate');
assert.strictEqual(S.severityOf(10, 4.99), 'moderate');
assert.strictEqual(S.severityOf(-10, -5), 'high');
ok('severity thresholds: normal below 1.5 %, moderate below 5 %, high from 5 %, tiny differences never alert');
assert.strictEqual(S.calcMetal('gold', { sold: 5, returned: 9 }).returnsExceedSales, true);
assert.strictEqual(S.calcMetal('gold', { sold: 5, returned: 9 }).out.sold, 0);
assert.strictEqual(S.calcMetal('gold', {}).variancePct, 0);
assert.strictEqual(S.calcMetal('gold', { purchased: 'abc', inShop: null }).variance, 0);
ok('returns larger than sales are flagged and never make sales negative; empty or bad input is zero');

// ── settings ──
assert.deepStrictEqual(S.resolveSettings(null), S.DEFAULT_SETTINGS);
assert.strictEqual(S.resolveSettings({ reconcile: { okPct: 2 } }).okPct, 2);
assert.strictEqual(S.resolveSettings({ reconcile: { okPct: 'x', goldAllowancePct: 500 } }).goldAllowancePct, 10, 'bad values fall back');
assert.strictEqual(S.resolveSettings({ reconcile: { okPct: 8, highPct: 3 } }).highPct, 5, 'high must be above normal');
assert.deepStrictEqual(S.validateSettings({ okPct: 2, silverAllowancePct: 15 }).set, { 'reconcile.okPct': 2, 'reconcile.silverAllowancePct': 15 });
assert(S.validateSettings({ okPct: -1 }).error && S.validateSettings({ nope: 1 }).error && S.validateSettings({ highPct: '' }).error);
ok('settings are validated and bad stored values fall back to the defaults');

// ── data checks ──
const checks = S.buildChecks({
    gold: { removedPieces: 155, removedG: 250.79, cancelledPendingPieces: 2, cancelledPendingG: 4.5, linesNoWeight: 3, pendingWastageCount: 1, pendingWastageG: 0.5, bulkEntries: 0, actionNeededPieces: 52, actionNeededG: 77.2 },
    silver: { returnsExceedSales: true, bulkEntries: 0 }, linesOtherMetal: 4, tallyDaysAgo: 90, duplicateBills: 1,
});
const ids = checks.map((x) => x.id);
for (const id of ['cancelled_not_restored', 'returns_exceed_sales', 'bill_lines_no_weight', 'bill_lines_other_metal', 'wastage_pending', 'pieces_need_details', 'pieces_removed', 'no_bulk_stock', 'tally_old', 'duplicate_bill_numbers']) assert(ids.includes(id), id);
assert.deepStrictEqual(checks.slice(0, 2).map((x) => x.level), ['error', 'error'], 'errors come first');
assert(checks.every((x) => x.en && x.bn && ['error', 'warn', 'info'].includes(x.level)), 'every finding has English and Bengali text');
assert(/4\.500/.test(checks.find((x) => x.id === 'cancelled_not_restored').en));
const conf = S.confidenceOf(checks);
assert.strictEqual(conf.level, 'fix');
assert.strictEqual(S.confidenceOf(S.buildChecks({ gold: { bulkEntries: 2 }, silver: { bulkEntries: 1 }, tallyDaysAgo: 10 })).level, 'reliable');
assert.strictEqual(S.confidenceOf(S.buildChecks({ gold: { bulkEntries: 1, linesNoWeight: 1 }, silver: { bulkEntries: 1 }, tallyDaysAgo: 10 })).level, 'check');
assert.strictEqual(S.buildChecks({ gold: { bulkEntries: 1 }, silver: { bulkEntries: 1 } }).find((x) => x.id === 'tally_never').level, 'warn');
const run = S.buildChecks({ gold: { bulkEntries: 1 }, silver: { bulkEntries: 1 }, tallyDaysAgo: 3, tallyRunning: { checked: 541, total: 635 } }).find((x) => x.id === 'tally_running');
assert(run && run.level === 'info' && /541 of 635/.test(run.en));
ok('data checks: each problem is found with what it means, errors first, and the confidence says whether to trust the number');

// ── insights ──
const short = S.calcMetal('gold', { purchased: 2326.91, inShop: 1405.34, sold: 809.988, wastage: 3.49 });
let ins = S.buildInsights('gold', short, { removedG: 250.79, pendingWastageG: 2, bulkEntries: 0, actionNeededPieces: 52 });
assert.strictEqual(ins.severity, 'high');
assert(/not accounted for/.test(ins.headline.en) && ins.headline.bn);
assert(ins.analysis.some((a) => /250\.790/.test(a.en)) && ins.analysis.some((a) => /waiting for approval/.test(a.en)) && ins.analysis.some((a) => /No bulk stock/.test(a.en)));
assert(ins.recommendations.length >= 4 && ins.recommendations.every((r) => r.en && r.bn));
ins = S.buildInsights('gold', S.calcMetal('gold', { purchased: 100, inShop: 100, sold: 10 }), {});
assert.strictEqual(ins.severity, 'normal');
assert(/balanced/.test(ins.headline.en));
ins = S.buildInsights('gold', S.calcMetal('gold', { purchased: 100, inShop: 100, sold: 15 }), {});
assert(/more than the records explain/.test(ins.headline.en) && ins.analysis.some((a) => /allowance/.test(a.en)));
ok('insights are built from the findings (removed pieces, pending wastage, missing bulk) in both languages');

// ── snapshots ──
const snapMetal = S.snapshotMetal(short);
assert(snapMetal.purchase_total === 2326.91 && snapMetal.calculated_purchase === 2559.601 && snapMetal.stock_total === 1405.34 && snapMetal.total_sold === 809.988 && snapMetal.final_result === 340.783 && snapMetal.wastage_total === 3.49);
assert.strictEqual(Math.round((snapMetal.expected_stock_debit - snapMetal.total_sold - snapMetal.wastage_total - snapMetal.final_result) * 1000) + 0, 0, "the old website's identity still holds: final = expected - sold - wastage");
const old = S.normalizeSnapshotMetal({ purchase_total: 100, calculated_purchase: 110, stock_total: 50, expected_stock_debit: 60, total_sold: 40, final_result: 15, discrepancy_percentage: 13.64 });
assert.strictEqual(old.wastage, 5, 'the old site stored no wastage: it follows from its formula (60 - 40 - 15)');
assert.strictEqual(old.out, 45);
ok('snapshots keep the website\'s field names and old snapshots are read the same way (wastage derived)');

// ── history ──
const mk = (date, stock, adj, sold, waste, variance, basis) => ({ date, basis, gold: { calculated_purchase: adj, stock_total: stock, total_sold: sold, wastage_total: waste, final_result: variance, expected_stock_debit: adj - stock, discrepancy_percentage: adj ? (variance / adj) * 100 : 0 }, silver: { calculated_purchase: 0, stock_total: 0, total_sold: 0, final_result: 0 } });
const snaps = [
    mk('2026-09-28', 100, 200, 60, 5, 35, undefined),      // the old website's (no basis)
    mk('2026-09-29', 105, 210, 62, 5, 38, undefined),
    mk('2026-10-05', 110, 230, 70, 6, 44, 'items'),
    mk('2026-10-06', 108, 230, 75, 6, 41, 'items'),
];
let rows = S.rollup(snaps, 'daily');
assert.strictEqual(rows.length, 4);
assert.strictEqual(rows[0].date, '2026-10-06');
assert.strictEqual(rows[3].gold.in, null, 'the first snapshot has nothing before it');
assert.strictEqual(rows[0].gold.in, 0);
assert.strictEqual(rows[0].gold.out, 5, '(75 + 6) - (70 + 6)');
assert.strictEqual(rows[1].gold.in, 20);                  // 230 - 210
assert.strictEqual(rows[1].methodChange, true, 'the day the method changed is marked');
assert.strictEqual(rows[2].methodChange, false);
assert.strictEqual(rows[3].methodChange, false);
ok('daily history: in / out are the CHANGE of the running totals, the first row has none, the change of method is marked');
rows = S.rollup(snaps, 'weekly');
assert.deepStrictEqual(rows.map((r) => r.key), ['2026-W41', '2026-W40']);
assert.strictEqual(rows[1].date, '2026-09-29', 'a week shows its LAST snapshot');
assert.strictEqual(rows[0].gold.stock, 108);
assert.strictEqual(rows[0].gold.in, 20, 'week 41 in = 230 - 210 (end of week 40)');
assert.strictEqual(rows[0].snapshots, 2);
rows = S.rollup(snaps, 'monthly');
assert.deepStrictEqual(rows.map((r) => r.label), ['Oct 2026', 'Sep 2026']);
assert.strictEqual(rows[0].gold.variance, 41);
assert.strictEqual(rows[1].gold.in, null);
ok('weekly and monthly history use the last snapshot of the period for balances (not an average)');
assert.strictEqual(S.weekKey('2026-01-01'), '2026-W01');
assert.strictEqual(S.weekKey('2025-12-29'), '2026-W01', 'ISO week: 29 Dec 2025 belongs to 2026-W01');
assert.strictEqual(S.weekKey('2027-01-03'), '2026-W53');
ok('ISO week numbers are right across year ends');
const tr = S.trend(S.rollup(snaps, 'daily'));
assert.strictEqual(tr.enough, true);
assert.strictEqual(tr.comparable, false, 'old and new method are not compared');
assert.strictEqual(tr.gold.stockChange, 8);
assert.strictEqual(tr.gold.varianceChange, 6);
assert.strictEqual(tr.gold.improving, false);
assert.strictEqual(S.trend([]).enough, false);
ok('the trend says whether its two ends are comparable');

console.log(`\nall stock-summary checks passed (${n})`);
