/**
 * dayBook.js - the maths of the Day Book: money that came in and went out in a period, by payment mode.
 *
 *   in  = payments received on invoices (Cash / Card / Online / Cheque; old metal taken as payment is NOT money)
 *   out = refunds paid on credit notes + expenses
 *   net = in - out   (the cash net of a day is what should be in the till, apart from the opening balance)
 * Pure: the controller fetches the records, this only adds them up.
 */
'use strict';

const MODES = ['Cash', 'Card', 'Online', 'Cheque'];
const r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;

/**
 * @param receipts  [{ at, title, subtitle, mode, amount }]  money in
 * @param outs      [{ at, kind: 'refund'|'expense', title, subtitle, mode, amount }]  money out
 */
function build(receipts, outs) {
    const modes = MODES.map((m) => ({ mode: m, in: 0, out: 0, net: 0 }));
    const row = (mode) => {
        let m = modes.find((x) => x.mode === mode);
        if (!m) { m = { mode: mode || 'Other', in: 0, out: 0, net: 0 }; modes.push(m); }
        return m;
    };
    const lines = [];
    for (const x of receipts || []) {
        row(x.mode).in += Number(x.amount) || 0;
        lines.push({ at: x.at || '', kind: 'receipt', title: x.title, subtitle: x.subtitle || '', mode: x.mode || 'Other', amount: r2(x.amount) });
    }
    for (const x of outs || []) {
        row(x.mode).out += Number(x.amount) || 0;
        lines.push({ at: x.at || '', kind: x.kind || 'expense', title: x.title, subtitle: x.subtitle || '', mode: x.mode || 'Other', amount: r2(x.amount) });
    }
    for (const m of modes) { m.in = r2(m.in); m.out = r2(m.out); m.net = r2(m.in - m.out); }
    const totals = { in: r2(modes.reduce((a, m) => a + m.in, 0)), out: r2(modes.reduce((a, m) => a + m.out, 0)) };
    totals.net = r2(totals.in - totals.out);
    lines.sort((a, b) => String(b.at).localeCompare(String(a.at)));
    return { modes, totals, lines };
}

module.exports = { MODES, build, r2 };
