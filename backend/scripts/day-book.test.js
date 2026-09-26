// Day Book maths: money in / out by payment mode. Run: node scripts/day-book.test.js
'use strict';
const assert = require('assert');
const DB = require('../services/dayBook');
let n = 0;
const t = (name, fn) => { fn(); n++; console.log('  ok  ', name); };

t('receipts add to "in", refunds and expenses to "out", per mode', () => {
    const b = DB.build(
        [{ at: '2026-09-26 10:00:00', title: 'A', mode: 'Cash', amount: 1000 }, { at: '2026-09-26 11:00:00', title: 'B', mode: 'Online', amount: 500.5 }, { at: '2026-09-26 12:00:00', title: 'C', mode: 'Cash', amount: 250 }],
        [{ at: '2026-09-26 13:00:00', kind: 'expense', title: 'Tea', mode: 'Cash', amount: 100 }, { at: '2026-09-26 14:00:00', kind: 'refund', title: 'R', mode: 'Online', amount: 200.25 }]);
    const m = (x) => b.modes.find((y) => y.mode === x);
    assert.deepStrictEqual([m('Cash').in, m('Cash').out, m('Cash').net], [1250, 100, 1150]);
    assert.deepStrictEqual([m('Online').in, m('Online').out, m('Online').net], [500.5, 200.25, 300.25]);
    assert.deepStrictEqual([m('Card').in, m('Cheque').in], [0, 0]);
    assert.deepStrictEqual([b.totals.in, b.totals.out, b.totals.net], [1750.5, 300.25, 1450.25]);
});

t('lines are newest first and carry their kind', () => {
    const b = DB.build([{ at: '2026-09-26 10:00:00', title: 'A', mode: 'Cash', amount: 1 }], [{ at: '2026-09-26 15:00:00', kind: 'expense', title: 'E', mode: 'Cash', amount: 1 }]);
    assert.deepStrictEqual(b.lines.map((l) => l.kind), ['expense', 'receipt']);
});

t('an unknown mode gets its own row instead of being lost; empty input gives zeros', () => {
    const b = DB.build([{ at: 'x', title: 'A', mode: 'UPI', amount: 40 }], []);
    assert.strictEqual(b.modes.find((m) => m.mode === 'UPI').in, 40);
    assert.strictEqual(b.totals.in, 40);
    const e = DB.build([], []);
    assert.deepStrictEqual([e.totals.in, e.totals.out, e.totals.net, e.lines.length], [0, 0, 0, 0]);
});

t('paise are kept exact (no float drift)', () => {
    const b = DB.build([0.1, 0.2, 0.3].map((a, i) => ({ at: String(i), title: 'x', mode: 'Cash', amount: a })), []);
    assert.strictEqual(b.totals.in, 0.6);
});

console.log(`\n${n} passed`);
