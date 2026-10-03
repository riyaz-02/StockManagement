'use strict';
/**
 * ONE collection for filed GST returns: the website's `gst_data` (services/gstFilings.js).
 * node scripts/gst-filings.test.js      (needs the local database; uses and drops a throw-away database)
 */
const assert = require('assert');
const { MongoClient } = require('mongodb');
const Filings = require('../services/gstFilings');

const DB = `gst_filings_test_${process.pid}`;
const ok = (m) => console.log(`ok - ${m}`);

(async () => {
    const client = await MongoClient.connect('mongodb://127.0.0.1:27018');
    const db = client.db(DB);
    const col = db.collection('gst_data');
    const o = { db };
    try {
        // what the PHP site wrote (flags and dates only): FY2025 Q1 and Q3
        await col.insertMany([
            { financial_year: 2025, quarter: 1, gstr1_filed: true, gstr3b_filed: true, gstr1_filed_date: '2025-07-07', gstr3b_filed_date: '2025-07-16', taxable_supplies: 1169886.7, gst_paid: 35096.6, itc_amount: 35096.6, remarks: '26624 ITC Left', created_at: new Date('2025-07-07') },
            { financial_year: 2025, quarter: 3, gstr1_filed: true, gstr3b_filed: true, gstr1_filed_date: '2026-01-08', gstr3b_filed_date: '2026-01-17', taxable_supplies: 487345.3, gst_paid: 14620.36, remarks: '11379 ITC Left Approx.', created_at: new Date('2026-01-08') },
        ]);
        const webBefore = JSON.stringify(await col.findOne({ financial_year: 2025, quarter: 3 }));

        // ── the old website's records are readable as filings ──
        let rows = await Filings.list({ gstin: '', ...o });
        assert.strictEqual(rows.length, 4);
        assert.deepStrictEqual(rows.map((r) => `${r.returnType}:${r.period}:${r.filedOn}`), ['GSTR-3B:2025-Q3:2026-01-17', 'GSTR-1:2025-Q3:2026-01-08', 'GSTR-3B:2025-Q1:2025-07-16', 'GSTR-1:2025-Q1:2025-07-07']);
        const q1b = rows.find((r) => r.returnType === 'GSTR-3B' && r.period === '2025-Q1');
        assert(q1b.source === 'website' && q1b.taxLiability === 35096.6 && q1b.itcUsed === 35096.6 && q1b.cashPaid === 0 && q1b.note === '26624 ITC Left');
        const q3b = rows.find((r) => r.returnType === 'GSTR-3B' && r.period === '2025-Q3');
        assert(q3b.itcUsed === 0 && q3b.cashPaid === 14620.36, 'no ITC recorded: all of it was paid in cash');
        ok('old website records (flags and dates) show as GSTR-1 / GSTR-3B filings with their amounts');

        // ── a new return goes into the same collection, one document per quarter ──
        const f1 = await Filings.create({ gstin: '', returnType: 'GSTR-1', period: '2025-Q4', filedOn: '2026-04-09', arn: 'AA1', taxLiability: 100, createdBy: '64b000000000000000000001', createdByName: 'Admin' }, o);
        assert(f1._id && f1.source === 'app' && f1.arn === 'AA1');
        assert.strictEqual(await col.countDocuments({}), 3);
        const d4 = await col.findOne({ financial_year: 2025, quarter: 4 });
        assert(d4.gstr1_filed === true && d4.gstr1_filed_date === '2026-04-09' && d4.gstr3b_filed === false && d4.filings.length === 1);
        ok('a return filed in the app is stored in the quarter\'s document and the website\'s own flag is set, so the old site shows it filed');

        await assert.rejects(() => Filings.create({ gstin: '', returnType: 'GSTR-3B', period: '2025-Q1', filedOn: '2025-07-20' }, o), (e) => e.code === 'DUPLICATE');
        await assert.rejects(() => Filings.create({ gstin: '', returnType: 'GSTR-1', period: '2025-Q4', filedOn: '2026-04-10' }, o), (e) => e.code === 'DUPLICATE');
        ok('a return already recorded (by the app or by the website) is refused as a duplicate');

        // ── monthly returns: the website's quarter flag is set when the third month is filed ──
        for (const [p, d] of [['2026-04', '2026-05-08'], ['2026-05', '2026-06-09']]) await Filings.create({ gstin: '', returnType: 'GSTR-1', period: p, filedOn: d }, o);
        let q = await col.findOne({ financial_year: 2026, quarter: 1 });
        assert.strictEqual(q.gstr1_filed, false, 'two of three months is not a filed quarter');
        await Filings.create({ gstin: '', returnType: 'GSTR-1', period: '2026-06', filedOn: '2026-07-10' }, o);
        q = await col.findOne({ financial_year: 2026, quarter: 1 });
        assert(q.gstr1_filed === true && q.gstr1_filed_date === '2026-07-10' && q.filings.length === 3);
        ok('monthly returns share the quarter\'s document; the website\'s flag turns on when all three months are filed');

        // ── other return types and other GSTINs live in the same document and never touch the website\'s flags ──
        await Filings.create({ gstin: '', returnType: 'PMT-06', period: '2026-08', filedOn: '2026-09-23', cashPaid: 50 }, o);
        await Filings.create({ gstin: '27AAAAA0000A1Z5', returnType: 'GSTR-3B', period: '2026-Q1', filedOn: '2026-07-21', arn: 'MB1', taxLiability: 700 }, o);
        const q2 = await col.findOne({ financial_year: 2026, quarter: 2 });
        assert(q2.gstr1_filed === false && q2.gstr3b_filed === false && q2.filings[0].returnType === 'PMT-06');
        q = await col.findOne({ financial_year: 2026, quarter: 1 });
        assert.strictEqual(q.gstr3b_filed, false, 'another GSTIN\'s return does not mark the default registration filed');
        assert.deepStrictEqual((await Filings.list({ gstin: '27AAAAA0000A1Z5', ...o })).map((r) => r.arn), ['MB1']);
        assert((await Filings.list({ gstin: '', ...o })).every((r) => r.gstin === ''));
        assert.strictEqual(await col.countDocuments({ financial_year: 2026, quarter: 1 }), 1, 'still ONE document per quarter');
        ok('PMT-06, GSTR-9, monthly and branch-GSTIN returns sit in the same quarter document without touching the website\'s flags');

        // ── editing: a record the website made becomes the app\'s own record (with the changes), no double ──
        const site = rows.find((r) => r._id.startsWith('site:') && r.returnType === 'GSTR-1' && r.period === '2025-Q1');
        const upd = await Filings.update(site._id, { arn: 'AA9999', note: 'ARN added later', updatedBy: 'u', updatedByName: 'Admin' }, o);
        assert(upd.arn === 'AA9999' && upd.source === 'app' && upd.filedOn === '2025-07-07');
        rows = await Filings.list({ gstin: '', type: 'GSTR-1', period: '2025-Q1', ...o });
        assert.strictEqual(rows.length, 1);
        const mine = rows[0];
        const again = await Filings.update(mine._id, { filedOn: '2025-07-08', updatedBy: 'u', updatedByName: 'Admin' }, o);
        assert(again.filedOn === '2025-07-08' && again.arn === 'AA9999');
        assert.strictEqual((await col.findOne({ financial_year: 2025, quarter: 1 })).gstr1_filed_date, '2025-07-08');
        ok('editing a website-made record keeps one record (now with the ARN); editing an app record updates the website\'s date too');

        // ── lookups the purchase lock and the calendar use ──
        const lock = await Filings.findOne({ type: 'GSTR-3B', periods: ['2025-07', '2025-Q1'], ...o });
        assert(lock && lock.period === '2025-Q1');
        assert.strictEqual(await Filings.findOne({ type: 'GSTR-3B', periods: ['2024-05', '2024-Q1'], ...o }), null);
        ok('"is this period filed?" finds website records too (used to lock purchases of a filed period)');

        // ── the website\'s own fields were never lost ──
        const web3 = await col.findOne({ financial_year: 2025, quarter: 3 });
        assert.strictEqual(JSON.stringify(web3), webBefore, 'an untouched quarter is byte-identical');
        const web1 = await col.findOne({ financial_year: 2025, quarter: 1 });
        assert(web1.taxable_supplies === 1169886.7 && web1.gst_paid === 35096.6 && web1.remarks === '26624 ITC Left');
        ok('the website\'s own fields (taxable supplies, GST paid, remarks) are never overwritten');

        console.log('\nall gst-filing checks passed');
    } finally {
        await db.dropDatabase().catch(() => {});
        await client.close();
    }
})().catch((e) => { console.error('FAILED:', e && e.stack || e); process.exit(1); });
