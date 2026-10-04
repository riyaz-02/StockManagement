/**
 * gstReports.js — everything behind the GST Summary page, as pure functions (no database, no clock),
 * so it can be tested to the paisa.
 *
 *   periods     monthly ("2026-08") or quarterly ("2026-Q2": financial-year quarters, FY starts in April)
 *   due dates   monthly filers:  GSTR-1 on the 11th, GSTR-3B on the 20th of the next month
 *               QRMP quarterly:  GSTR-1 on the 13th, GSTR-3B on the 22nd or 24th (by the state of registration),
 *                                plus a monthly tax payment (PMT-06) on the 25th for the first two months
 *               annual:          GSTR-9 on 31 December after the financial year
 *   ITC         utilised in the order the law requires (Section 49(5) / Rule 88A):
 *               IGST credit -> IGST, then CGST, then SGST liability;
 *               CGST credit -> CGST, then IGST;  SGST credit -> SGST, then IGST.  CGST credit can never pay SGST.
 *   summaries   built from invoices mapped by billingView.toView (so legacy website invoices work too).
 *
 * The person filing (or the CA) remains responsible for what is filed: this page prepares the numbers.
 */
'use strict';

const { toView, HIDDEN_STATUSES } = require('./billingView');

const r2 = (n) => Math.round(((Number(n) || 0) + Number.EPSILON) * 100) / 100;
const r3 = (n) => Math.round(((Number(n) || 0) + Number.EPSILON) * 1000) / 1000;
const pad = (n) => String(n).padStart(2, '0');
const YMD = /^\d{4}-\d{2}-\d{2}$/;

// ── dates ────────────────────────────────────────────────────────────────────
const parse = (ymd) => { const [y, m, d] = String(ymd).slice(0, 10).split('-').map(Number); return { y, m, d }; };
const fmt = (y, m, d) => `${y}-${pad(m)}-${pad(d)}`;
const lastDay = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();
const addMonths = (y, m, n) => { const t = y * 12 + (m - 1) + n; return { y: Math.floor(t / 12), m: (t % 12) + 1 }; };
const utcDay = (ymd) => { const { y, m, d } = parse(ymd); return Date.UTC(y, m - 1, d); };
const daysBetween = (fromYmd, toYmd) => Math.round((utcDay(toYmd) - utcDay(fromYmd)) / 86400000);
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTHS_FULL = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

const fyStartYear = (y, m) => (m >= 4 ? y : y - 1);
const fyLabel = (startYear) => `${startYear}-${String((startYear + 1) % 100).padStart(2, '0')}`;

/** Which return period a date falls in. */
function periodKey(frequency, ymd) {
    const { y, m } = parse(ymd);
    if (frequency === 'quarterly') {
        const fy = fyStartYear(y, m);
        const q = Math.floor(((m - 4 + 12) % 12) / 3) + 1;
        return `${fy}-Q${q}`;
    }
    return `${y}-${pad(m)}`;
}

/** {from, to, label, months:[{y,m}], kind} for "2026-08" or "2026-Q2" (Q2 of FY 2026-27 = Jul-Sep 2026). */
function periodRange(key) {
    let mm = /^(\d{4})-Q([1-4])$/.exec(key);
    if (mm) {
        const fy = Number(mm[1]), q = Number(mm[2]);
        const start = addMonths(fy, 4, (q - 1) * 3);
        const end = addMonths(start.y, start.m, 2);
        return {
            key, kind: 'quarter', from: fmt(start.y, start.m, 1), to: fmt(end.y, end.m, lastDay(end.y, end.m)),
            label: `Q${q} FY ${fyLabel(fy)} (${MONTHS[start.m - 1]}–${MONTHS[end.m - 1]} ${end.y})`, short: `Q${q} ${fyLabel(fy)}`,
            months: [0, 1, 2].map((i) => addMonths(start.y, start.m, i)),
        };
    }
    mm = /^(\d{4})-(\d{2})$/.exec(key);
    if (mm) {
        const y = Number(mm[1]), m = Number(mm[2]);
        if (m < 1 || m > 12) return null;
        return { key, kind: 'month', from: fmt(y, m, 1), to: fmt(y, m, lastDay(y, m)), label: `${MONTHS_FULL[m - 1]} ${y}`, short: `${MONTHS[m - 1]} ${y}`, months: [{ y, m }] };
    }
    return null;
}

const nextPeriodKey = (key) => {
    const p = periodRange(key);
    const nx = addMonths(parse(p.to).y, parse(p.to).m, 1);
    return periodKey(p.kind === 'quarter' ? 'quarterly' : 'monthly', fmt(nx.y, nx.m, 1));
};

/** Consecutive period keys covering [fromYmd, toYmd]. */
function listPeriods(frequency, fromYmd, toYmd) {
    const out = [];
    let key = periodKey(frequency, fromYmd);
    const last = periodKey(frequency, toYmd);
    for (let i = 0; i < 400; i++) {
        out.push(key);
        if (key === last) break;
        key = nextPeriodKey(key);
    }
    return out;
}

// ── due dates ────────────────────────────────────────────────────────────────
// States whose QRMP GSTR-3B falls on the 22nd; every other state / UT files on the 24th.
const QRMP_22 = new Set(['22', '23', '24', '26', '27', '29', '30', '31', '32', '33', '34', '35', '36', '37']);
const qrmpDay3b = (stateCode) => (QRMP_22.has(String(stateCode || '').padStart(2, '0')) ? 22 : 24);

const RETURN_TYPES = ['GSTR-1', 'GSTR-3B', 'PMT-06', 'GSTR-9'];
const RETURN_TITLES = {
    'GSTR-1': 'GSTR-1 (sales return)',
    'GSTR-3B': 'GSTR-3B (summary + tax payment)',
    'PMT-06': 'Monthly tax payment (PMT-06)',
    'GSTR-9': 'GSTR-9 (annual return)',
};

/** Statutory due date of one return for one period. (Weekends / notified extensions are not applied.) */
function dueDate(type, key, { frequency = 'monthly', stateCode = '19' } = {}) {
    if (type === 'GSTR-9') {
        const m = /^FY(\d{4})$/.exec(key);
        if (!m) return null;
        return fmt(Number(m[1]) + 1, 12, 31);          // FY 2026-27 (FY2026) -> 31 December 2027
    }
    const p = periodRange(key);
    if (!p) return null;
    const end = parse(p.to);
    const nx = addMonths(end.y, end.m, 1);
    if (type === 'PMT-06') return fmt(nx.y, nx.m, 25);
    if (p.kind === 'quarter') return fmt(nx.y, nx.m, type === 'GSTR-1' ? 13 : qrmpDay3b(stateCode));
    return fmt(nx.y, nx.m, type === 'GSTR-1' ? 11 : 20);
}

/**
 * Every return obligation whose due date falls in [fromYmd, toYmd], oldest first.
 * Each: {type, period, periodLabel, due, title}
 */
function obligations(settings, fromYmd, toYmd) {
    const freq = settings.frequency === 'quarterly' ? 'quarterly' : 'monthly';
    const ctx = { frequency: freq, stateCode: settings.stateCode || '19' };
    const start = addMonths(parse(fromYmd).y, parse(fromYmd).m, -4);      // due dates trail their period by up to ~3 months
    const periods = listPeriods(freq, fmt(start.y, start.m, 1), toYmd);
    const list = [];
    const push = (type, key, label) => {
        const due = dueDate(type, key, ctx);
        if (due && due >= fromYmd && due <= toYmd) list.push({ type, period: key, periodLabel: label, due, title: RETURN_TITLES[type] });
    };
    for (const key of periods) {
        const p = periodRange(key);
        push('GSTR-1', key, p.label);
        push('GSTR-3B', key, p.label);
        if (freq === 'quarterly') {
            // the first two months of each quarter are paid monthly by challan (PMT-06)
            p.months.slice(0, 2).forEach((mo) => push('PMT-06', `${mo.y}-${pad(mo.m)}`, `${MONTHS_FULL[mo.m - 1]} ${mo.y}`));
        }
    }
    // annual return for every financial year whose 31 December falls in the window
    for (let fy = parse(fromYmd).y - 2; fy <= parse(toYmd).y; fy++) {
        const due = dueDate('GSTR-9', `FY${fy}`);
        if (due && due >= fromYmd && due <= toYmd) list.push({ type: 'GSTR-9', period: `FY${fy}`, periodLabel: `FY ${fyLabel(fy)}`, due, title: RETURN_TITLES['GSTR-9'] });
    }
    return list.sort((a, b) => a.due.localeCompare(b.due) || a.type.localeCompare(b.type));
}

/**
 * Obligations with their status against the recorded filings.
 *   filed | overdue | due-soon (<= soonDays) | upcoming
 */
function statusList(settings, filings, todayYmd, { back = 120, ahead = 200, soonDays = 7 } = {}) {
    const t = parse(todayYmd);
    const from = addMonths(t.y, t.m, 0); const f = addMonths(from.y, from.m, -Math.ceil(back / 30));
    const to = addMonths(t.y, t.m, Math.ceil(ahead / 30));
    const fromYmd = fmt(f.y, f.m, 1), toYmd = fmt(to.y, to.m, lastDay(to.y, to.m));
    const byKey = new Map((filings || []).map((x) => [`${x.returnType}|${x.period}`, x]));
    // Periods that ended before "track filings from" are not followed (no false "overdue" for years the app never saw).
    const startTrack = /^\d{4}-\d{2}$/.test(settings.remindersFrom || '') ? `${settings.remindersFrom}-01` : '0000-00-00';
    const periodEnd = (o) => {
        if (o.type === 'GSTR-9') return fmt(Number(o.period.slice(2)) + 1, 3, 31);
        const p = periodRange(o.period);
        return p ? p.to : '9999-99-99';
    };
    return obligations(settings, fromYmd, toYmd).map((o) => {
        const filing = byKey.get(`${o.type}|${o.period}`) || null;
        const daysLeft = daysBetween(todayYmd, o.due);
        const tracked = periodEnd(o) >= startTrack;
        const status = filing ? 'filed' : !tracked ? 'untracked' : daysLeft < 0 ? 'overdue' : daysLeft <= soonDays ? 'due-soon' : 'upcoming';
        return { ...o, daysLeft, status, filing };
    });
}

/** Alerts to show: overdue (last 90 days) and anything due within the biggest reminder lead time. */
function alerts(settings, filings, todayYmd) {
    const lead = Math.max(0, ...((settings.reminders && settings.reminders.daysBefore) || [7]));
    return statusList(settings, filings, todayYmd)
        .filter((o) => o.status !== 'filed' && o.status !== 'untracked' && ((o.daysLeft < 0 && o.daysLeft >= -90) || (o.daysLeft >= 0 && o.daysLeft <= lead)))
        .map((o) => ({ ...o, severity: o.daysLeft < 0 ? 'overdue' : o.daysLeft <= 3 ? 'urgent' : 'info' }))
        .sort((a, b) => a.due.localeCompare(b.due));
}

/**
 * Reminder messages that should go out now. `sentKeys` = keys already sent. The server can be asleep on the exact
 * day (see scheduledNotifications.js), so a reminder fires as soon as its lead time has been reached, once.
 */
function pendingReminders(settings, filings, todayYmd, sentKeys = new Set()) {
    const cfg = settings.reminders || {};
    if (cfg.enabled === false) return [];
    const offsets = [...new Set((cfg.daysBefore && cfg.daysBefore.length ? cfg.daysBefore : [7, 3, 1, 0]).map(Number))].sort((a, b) => a - b);
    const out = [];
    for (const o of statusList(settings, filings, todayYmd)) {
        if (o.status === 'filed' || o.status === 'untracked') continue;
        const base = `${o.type}|${o.period}`;
        if (o.daysLeft >= 0) {
            const reached = offsets.filter((d) => o.daysLeft <= d && !sentKeys.has(`${base}|d${d}`));
            if (!reached.length) continue;
            const when = o.daysLeft === 0 ? 'is due TODAY' : o.daysLeft === 1 ? 'is due tomorrow' : `is due in ${o.daysLeft} days`;
            out.push({ keys: reached.map((d) => `${base}|d${d}`), title: `${o.type} ${when}`, body: `${o.title} for ${o.periodLabel}: due ${o.due}. Mark it as filed in GST Summary once done.`, obligation: o });
        } else if (cfg.overdue !== false && o.daysLeft >= -10) {
            const key = `${base}|over${todayYmd}`;
            if (sentKeys.has(key)) continue;
            out.push({ keys: [key], title: `${o.type} is OVERDUE`, body: `${o.title} for ${o.periodLabel} was due on ${o.due} (${-o.daysLeft} day${o.daysLeft === -1 ? '' : 's'} ago). Late fee and interest may apply.`, obligation: o });
        }
    }
    return out;
}

// ── input tax credit ─────────────────────────────────────────────────────────
/**
 * Pay liabilities from credits in the order the law requires.
 *   liab   {igst, cgst, sgst}   tax to pay
 *   credit {igst, cgst, sgst}   ITC available
 * -> { used: {igst:{igst,cgst,sgst}, cgst:{cgst,igst}, sgst:{sgst,igst}}, cash:{igst,cgst,sgst}, remaining:{igst,cgst,sgst} }
 */
function utilise(liab, credit) {
    const L = { igst: r2(liab.igst), cgst: r2(liab.cgst), sgst: r2(liab.sgst) };
    const C = { igst: r2(credit.igst), cgst: r2(credit.cgst), sgst: r2(credit.sgst) };
    const used = { igst: { igst: 0, cgst: 0, sgst: 0 }, cgst: { cgst: 0, igst: 0 }, sgst: { sgst: 0, igst: 0 } };
    const take = (from, to, bucket, key) => {
        const x = Math.min(C[from], L[to]);
        if (x > 0) { C[from] = r2(C[from] - x); L[to] = r2(L[to] - x); bucket[key] = r2(bucket[key] + x); }
    };
    // IGST credit first: against IGST, then CGST, then SGST
    take('igst', 'igst', used.igst, 'igst'); take('igst', 'cgst', used.igst, 'cgst'); take('igst', 'sgst', used.igst, 'sgst');
    // CGST credit: against CGST, then IGST
    take('cgst', 'cgst', used.cgst, 'cgst'); take('cgst', 'igst', used.cgst, 'igst');
    // SGST credit: against SGST, then IGST
    take('sgst', 'sgst', used.sgst, 'sgst'); take('sgst', 'igst', used.sgst, 'igst');
    return { used, cash: L, remaining: C };
}

const zeroT = () => ({ igst: 0, cgst: 0, sgst: 0 });
const sumT = (a, b) => ({ igst: r2(a.igst + b.igst), cgst: r2(a.cgst + b.cgst), sgst: r2(a.sgst + b.sgst) });
const totalOf = (t) => r2(t.igst + t.cgst + t.sgst);

/**
 * Roll ITC forward period by period.
 *   periods        [{key, liability:{igst,cgst,sgst}, itc:{igst,cgst,sgst}}] oldest first
 *   opening        credit carried into the first period
 * -> [{key, opening, added, available, liability, used, cash, closing}]
 */
function itcLedger(periods, opening) {
    let bal = { igst: r2(opening.igst), cgst: r2(opening.cgst), sgst: r2(opening.sgst) };
    return periods.map((p) => {
        const avail = sumT(bal, p.itc);
        const u = utilise(p.liability, avail);
        const row = { key: p.key, opening: bal, added: p.itc, available: avail, liability: p.liability, used: u.used, cash: u.cash, closing: u.remaining };
        bal = u.remaining;
        return row;
    });
}

// ── invoices -> numbers ──────────────────────────────────────────────────────
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const istYmd = (iso) => {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return String(iso).slice(0, 10);
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
};

/** "Gold Ring (HUID: AB12CD) + Making Charge" -> "Gold Ring" (grouping key for item-wise sales). */
const baseName = (line) => {
    const n = (line.itemName || line.particular || '').replace(/\s*\+\s*Making Charge\s*$/i, '').replace(/\s*\((Hallmarked|HUID:[^)]*)\)\s*$/i, '').trim();
    return n || 'Unnamed';
};

/** What part of a line's taxable value is making charge: the making column, or (typed taxable amount) what is left after metal, stones and hallmark. */
function lineMaking(l) {
    const metal = num(l.netWt) * num(l.rate);
    return r2(Math.max(0, num(l.taxableAmount) - metal - num(l.stoneCharge) - (l.hallmarkTaxed === false ? 0 : num(l.hallmarkCharge))));   // since rule v3 the hallmark fee is outside the taxable amount
}

const isHidden = (v) => !v.counts;

const groupKey = (group, ymd) => {
    const { y, m, d } = parse(ymd);
    if (group === 'day') return ymd;
    if (group === 'week') {                     // week starting Monday
        const dt = new Date(Date.UTC(y, m - 1, d));
        const dow = (dt.getUTCDay() + 6) % 7;
        dt.setUTCDate(dt.getUTCDate() - dow);
        return `${dt.getUTCFullYear()}-${pad(dt.getUTCMonth() + 1)}-${pad(dt.getUTCDate())}`;
    }
    if (group === 'quarter') return periodKey('quarterly', ymd);
    return `${y}-${pad(m)}`;
};
const groupLabel = (group, key) => {
    if (group === 'day' || group === 'week') { const { m, d } = parse(key); return `${d} ${MONTHS[m - 1]}`; }
    const p = periodRange(key);
    return p ? p.short : key;
};

/**
 * Summarise invoices (raw documents from the live `invoices` collection).
 * opts: {from, to, group, metal, taxType:'intra'|'inter', min, max, q, branch, b2clThreshold}
 */
function summarise(docs, opts = {}) {
    const views = docs.map((d) => toView(d));
    const from = opts.from || '0000-00-00', to = opts.to || '9999-99-99';
    const metalF = opts.metal ? String(opts.metal).toLowerCase() : '';
    const q = opts.q ? String(opts.q).toLowerCase() : '';
    const min = opts.min != null && opts.min !== '' ? num(opts.min) : null;
    const max = opts.max != null && opts.max !== '' ? num(opts.max) : null;
    const threshold = opts.b2clThreshold != null ? num(opts.b2clThreshold) : 100000;
    const group = ['day', 'week', 'month', 'quarter'].includes(opts.group) ? opts.group : 'month';

    const T = { invoices: 0, invoiceValue: 0, taxable: 0, cgst: 0, sgst: 0, igst: 0, tax: 0, weight: 0, metalValue: 0, making: 0, stones: 0, hallmark: 0, extraCharges: 0, extraChargesGst: 0, discount: 0, roundOff: 0, tds: 0, paid: 0, due: 0, intra: 0, inter: 0 };
    const byMetal = new Map(), byItem = new Map(), byPurity = new Map(), byHsn = new Map(), byPlace = new Map(), trend = new Map(), pay = new Map();
    const b2cl = [], series = new Map();
    const notes = { untaxedExtraCharges: 0, untaxedExtraAmount: 0, discountAfterGst: 0, cancelled: 0, filteredOut: 0 };
    const rows = [];
    const bump = (map, key, init) => { if (!map.has(key)) map.set(key, init()); return map.get(key); };
    const lineBased = !!metalF;

    for (const v of views) {
        const d = (YMD.test(v.invoiceDate) ? v.invoiceDate : istYmd(v.createdAt)) || '';
        if (!d || d < from || d > to) continue;
        // numbering series: plain 4-digit numbers are the main series; "BR2-0001" is series BR2
        const nm = /^([A-Za-z][A-Za-z0-9]*)-(\d+)$/.exec(String(v.invoiceNumber));
        const seriesKey = nm ? nm[1] : 'MAIN';
        const numPart = nm ? parseInt(nm[2], 10) : (/^\d+$/.test(String(v.invoiceNumber)) ? parseInt(v.invoiceNumber, 10) : null);
        const ser = bump(series, seriesKey, () => ({ series: seriesKey, min: null, max: null, total: 0, cancelled: 0 }));
        if (numPart != null) { ser.min = ser.min == null ? numPart : Math.min(ser.min, numPart); ser.max = ser.max == null ? numPart : Math.max(ser.max, numPart); }
        ser.total++;
        if (isHidden(v)) { ser.cancelled++; notes.cancelled++; continue; }

        // ── filters (whole-invoice) ──
        const lines = metalF ? v.items.filter((l) => String(l.metalType).toLowerCase() === metalF) : v.items;
        const inter = v.gstSummary.igst > 0 || v.gstType === 'IGST';
        if (opts.branch && v.branchId !== opts.branch) { notes.filteredOut++; continue; }
        if (metalF && !lines.length) { notes.filteredOut++; continue; }
        if (opts.taxType === 'inter' && !inter) { notes.filteredOut++; continue; }
        if (opts.taxType === 'intra' && inter) { notes.filteredOut++; continue; }
        if (min != null && v.totalPayableAmount < min) { notes.filteredOut++; continue; }
        if (max != null && v.totalPayableAmount > max) { notes.filteredOut++; continue; }
        if (q && !`${v.invoiceNumber} ${v.customerName} ${v.customerMobile}`.toLowerCase().includes(q)) { notes.filteredOut++; continue; }

        const v2 = v.discountMode === 'before_gst';
        const extra = v.additionalCharges || 0;
        const extraTaxable = v2 ? extra : 0, extraGst = v2 ? num(v.additionalChargesGst) : 0;
        if (!v2 && extra > 0) { notes.untaxedExtraCharges++; notes.untaxedExtraAmount = r2(notes.untaxedExtraAmount + extra); }
        if (!v2 && v.discount > 0) notes.discountAfterGst++;

        // line-level numbers (always from the lines actually included)
        let iTaxable = 0, iCgst = 0, iSgst = 0, iIgst = 0, iWeight = 0, iMetalValue = 0, iMaking = 0, iStones = 0, iHall = 0;
        for (const l of lines) {
            const making = lineMaking(l), metalVal = r2(num(l.netWt) * num(l.rate));
            iTaxable += l.taxableAmount; iCgst += l.cgst; iSgst += l.sgst; iIgst += l.igst; iWeight += l.netWt; iMetalValue += metalVal; iMaking += making; iStones += l.stoneCharge; iHall += l.hallmarkCharge;

            const m = bump(byMetal, l.metalType || 'Other', () => ({ metal: l.metalType || 'Other', weight: 0, metalValue: 0, making: 0, taxable: 0, tax: 0, total: 0, pieces: 0, invoices: new Set() }));
            m.weight += l.netWt; m.metalValue += metalVal; m.making += making; m.taxable += l.taxableAmount; m.tax += l.cgst + l.sgst + l.igst; m.total += l.total; m.pieces++; m.invoices.add(v.invoiceNumber);
            const nm = baseName(l);
            const it = bump(byItem, `${(l.metalType || 'Other').toLowerCase()}|${nm.toLowerCase()}`, () => ({ item: nm, metal: l.metalType || 'Other', pieces: 0, weight: 0, taxable: 0, making: 0, tax: 0, total: 0, invoices: new Set() }));
            it.pieces++; it.weight += l.netWt; it.taxable += l.taxableAmount; it.making += making; it.tax += l.cgst + l.sgst + l.igst; it.total += l.total; it.invoices.add(v.invoiceNumber);
            const pk = `${l.metalType || 'Other'}|${l.purity || 'Not recorded'}`;
            const pu = bump(byPurity, pk, () => ({ metal: l.metalType || 'Other', purity: l.purity || 'Not recorded', pieces: 0, weight: 0, taxable: 0 }));
            pu.pieces++; pu.weight += l.netWt; pu.taxable += l.taxableAmount;
            const hs = bump(byHsn, l.hsnCode || '7113', () => ({ hsn: l.hsnCode || '7113', qty: 0, value: 0, taxable: 0, cgst: 0, sgst: 0, igst: 0 }));
            hs.qty += l.netWt; hs.value += l.total - (l.hallmarkTaxed === false ? num(l.hallmarkCharge) : 0);   // HSN value = goods + tax: a passed-on hallmark fee is not part of it
            hs.taxable += l.taxableAmount; hs.cgst += l.cgst; hs.sgst += l.sgst; hs.igst += l.igst;
        }
        // extra charges are part of the supply: file them under the first line's HSN so the HSN table reconciles
        if (!lineBased && (extraTaxable || extraGst) && v.items.length) {
            const hs = byHsn.get(v.items[0].hsnCode || '7113');
            if (hs) { hs.taxable += extraTaxable; hs.value += extraTaxable + extraGst; if (inter) hs.igst += extraGst; else { hs.cgst += extraGst / 2; hs.sgst += extraGst / 2; } }
        }
        const mExtra = !lineBased && (extraTaxable || extraGst);
        if (mExtra) {
            const m = bump(byMetal, 'Extra charges', () => ({ metal: 'Extra charges', weight: 0, metalValue: 0, making: 0, taxable: 0, tax: 0, total: 0, pieces: 0, invoices: new Set() }));
            m.taxable += extraTaxable; m.tax += extraGst; m.total += extraTaxable + extraGst; m.invoices.add(v.invoiceNumber);
        }

        // invoice-level totals: the invoice's own GST summary when the whole invoice counts, else the included lines
        const taxable = lineBased ? iTaxable : v.gstSummary.taxableValue;
        const cgst = lineBased ? iCgst : v.gstSummary.cgst, sgst = lineBased ? iSgst : v.gstSummary.sgst, igst = lineBased ? iIgst : v.gstSummary.igst;
        const value = lineBased ? r2(lines.reduce((a, l) => a + l.total, 0)) : v.totalPayableAmount;

        T.invoices++; T.invoiceValue += value; T.taxable += taxable; T.cgst += cgst; T.sgst += sgst; T.igst += igst; T.tax += cgst + sgst + igst;
        T.weight += iWeight; T.metalValue += iMetalValue; T.making += iMaking; T.stones += iStones; T.hallmark += iHall;
        if (!lineBased) { T.extraCharges += extra; T.extraChargesGst += extraGst; T.discount += v.discountGiven; T.roundOff += v.roundOff; T.tds += v.tds.amount; T.paid += v.paidAmount; T.due += v.dueAmount; }
        if (inter) T.inter++; else T.intra++;

        const place = v.placeOfSupply || '19-West Bengal';
        const pl = bump(byPlace, place, () => ({ place, invoices: 0, taxable: 0, cgst: 0, sgst: 0, igst: 0, value: 0, inter }));
        pl.invoices++; pl.taxable += taxable; pl.cgst += cgst; pl.sgst += sgst; pl.igst += igst; pl.value += value;

        if (inter && value > threshold) b2cl.push({ number: v.invoiceNumber, date: d, place, value: r2(value), taxable: r2(taxable), igst: r2(igst) });

        const gk = groupKey(group, d);
        const tr = bump(trend, gk, () => ({ key: gk, label: groupLabel(group, gk), invoices: 0, taxable: 0, tax: 0, value: 0, weight: 0 }));
        tr.invoices++; tr.taxable += taxable; tr.tax += cgst + sgst + igst; tr.value += value; tr.weight += iWeight;

        // payments received within the period, by mode
        for (const p of v.paymentHistory) {
            const pd = istYmd(p.date);
            if (pd && pd >= from && pd <= to) { const pm = bump(pay, p.mode || 'Cash', () => ({ mode: p.mode || 'Cash', amount: 0, count: 0 })); pm.amount += p.amount; pm.count++; }
        }

        rows.push({
            _id: v._id, invoiceNumber: v.invoiceNumber, date: d, customerName: v.customerName, customerMobile: v.customerMobile, branchName: v.branchName,
            place, taxType: inter ? 'IGST' : 'CGST+SGST', taxable: r2(taxable), cgst: r2(cgst), sgst: r2(sgst), igst: r2(igst), tax: r2(cgst + sgst + igst),
            value: r2(value), weight: r3(iWeight), making: r2(iMaking), metals: [...new Set(lines.map((l) => l.metalType))].join(', '), status: v.status, paid: v.paidAmount, due: v.dueAmount,
        });
    }

    const list = (map, f) => [...map.values()].map(f);
    const roundAll = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, typeof v === 'number' ? (k === 'weight' || k === 'qty' ? r3(v) : r2(v)) : v]));
    const totals = roundAll(T);
    totals.avgRate = totals.weight > 0 ? r2(totals.metalValue / totals.weight) : 0;
    totals.taxRate = totals.taxable > 0 ? r2((totals.tax / totals.taxable) * 100) : 0;

    const b2csMap = new Map();
    for (const pl of byPlace.values()) {
        // small B2C: everything except the large inter-state invoices reported one by one
        const large = b2cl.filter((x) => x.place === pl.place);
        const lt = large.reduce((a, x) => a + x.taxable, 0), li = large.reduce((a, x) => a + x.igst, 0);
        const taxable = pl.taxable - lt;
        if (taxable > 0.005 || pl.igst - li > 0.005 || pl.cgst > 0.005) b2csMap.set(pl.place, { place: pl.place, rate: 3, taxable: r2(taxable), igst: r2(pl.igst - li), cgst: r2(pl.cgst), sgst: r2(pl.sgst), inter: pl.inter });
    }

    return {
        range: { from: opts.from || null, to: opts.to || null, group },
        lineBased,
        totals,
        byMetal: list(byMetal, (m) => ({ ...roundAll(m), invoices: m.invoices.size, avgRate: m.weight > 0 ? r2(m.metalValue / m.weight) : 0 })).sort((a, b) => b.taxable - a.taxable),
        byItem: list(byItem, (m) => ({ ...roundAll(m), invoices: m.invoices.size })).sort((a, b) => b.taxable - a.taxable),
        byPurity: list(byPurity, roundAll).sort((a, b) => b.weight - a.weight),
        byPlace: list(byPlace, roundAll).sort((a, b) => b.taxable - a.taxable),
        payments: list(pay, roundAll).sort((a, b) => b.amount - a.amount),
        trend: list(trend, roundAll).sort((a, b) => a.key.localeCompare(b.key)),
        gstr1: {
            b2cs: [...b2csMap.values()].sort((a, b) => a.place.localeCompare(b.place)),
            b2cl: b2cl.sort((a, b) => a.date.localeCompare(b.date)),
            hsn: list(byHsn, (h) => ({ ...roundAll(h), uqc: 'GMS' })).sort((a, b) => a.hsn.localeCompare(b.hsn)),
            docs: list(series, (s) => ({ ...s, from: s.min == null ? '' : s.series === 'MAIN' ? String(s.min).padStart(4, '0') : `${s.series}-${String(s.min).padStart(4, '0')}`, to: s.max == null ? '' : s.series === 'MAIN' ? String(s.max).padStart(4, '0') : `${s.series}-${String(s.max).padStart(4, '0')}`, net: s.total - s.cancelled })),
            b2clThreshold: threshold,
        },
        notes: { ...notes, untaxedExtraAmount: r2(notes.untaxedExtraAmount) },
        rows,
    };
}

/** Sort + page the invoice register. */
function registerPage(rows, { sort = 'date', dir = 'desc', page = 1, limit = 50 } = {}) {
    const keys = ['date', 'invoiceNumber', 'customerName', 'value', 'taxable', 'tax', 'weight', 'making', 'due'];
    const k = keys.includes(sort) ? sort : 'date';
    const sgn = dir === 'asc' ? 1 : -1;
    const sorted = rows.slice().sort((a, b) => {
        const x = a[k], y = b[k];
        const c = typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y), undefined, { numeric: true });
        return c * sgn || String(b.invoiceNumber).localeCompare(String(a.invoiceNumber), undefined, { numeric: true });
    });
    const lim = Math.max(1, Math.min(200, Number(limit) || 50)), pg = Math.max(1, Number(page) || 1);
    return { total: sorted.length, page: pg, limit: lim, rows: sorted.slice((pg - 1) * lim, pg * lim) };
}

/** Tax liability of a summary, as {igst, cgst, sgst}. */
const liabilityOf = (summary) => ({ igst: r2(summary.totals.igst), cgst: r2(summary.totals.cgst), sgst: r2(summary.totals.sgst) });

/** ITC of purchases (documents from `purchases`) dated within [from, to]. Purchases without a supplier GSTIN are not claimable. */
function purchaseItc(purchases, from, to, { countWithoutGstin = false } = {}) {
    const claim = zeroT(), atRisk = zeroT();
    let count = 0, riskCount = 0, taxable = 0;
    for (const p of purchases || []) {
        if (p.isDeleted) continue;
        const d = istYmd(p.invoiceDate);
        if (!d || d < from || d > to) continue;
        const t = { igst: num(p.itcIgst), cgst: num(p.itcCgst), sgst: num(p.itcSgst) };
        if (!(totalOf(t) > 0)) continue;
        const ok = countWithoutGstin || String(p.billerGstin || '').trim().length >= 15;
        if (ok) { claim.igst += t.igst; claim.cgst += t.cgst; claim.sgst += t.sgst; count++; taxable += num(p.totalAmount); }
        else { atRisk.igst += t.igst; atRisk.cgst += t.cgst; atRisk.sgst += t.sgst; riskCount++; }
    }
    return { claim: { igst: r2(claim.igst), cgst: r2(claim.cgst), sgst: r2(claim.sgst) }, atRisk: { igst: r2(atRisk.igst), cgst: r2(atRisk.cgst), sgst: r2(atRisk.sgst) }, count, riskCount, purchaseValue: r2(taxable) };
}

// ── checks before filing ────────────────────────────────────────────────────
/**
 * Things in the period's own invoices that a GST officer (or your CA) would ask about. Each check is
 *   {id, severity: 'warn' | 'info', title, detail, invoices: [numbers], more: count not listed}
 * Only invoices that count (not cancelled / void / deleted) are checked, except the numbering check which needs them all.
 */
function complianceChecks(docs, from, to, { addressLimit = 50000, cashLimit = 200000, panLimit = 200000 } = {}) {
    const views = [];
    for (const d of docs || []) {
        const v = toView(d);
        const date = (YMD.test(v.invoiceDate) ? v.invoiceDate : istYmd(v.createdAt)) || '';
        if (date && date >= from && date <= to) views.push({ v, date });
    }
    const valid = views.filter((x) => !isHidden(x.v));
    const out = [];
    const add = (id, severity, title, detail, list) => {
        if (!list.length) return;
        out.push({ id, severity, title, detail, invoices: list.slice(0, 12), more: Math.max(0, list.length - 12), count: list.length });
    };
    const numbers = (arr) => arr.map((x) => x.v.invoiceNumber);

    add('address', 'warn', 'Buyer address missing on bills of ₹50,000 or more',
        'GST Rule 46 requires the name and address of an unregistered buyer on such an invoice. Add the address on the invoice (old invoices can be amended on the website).',
        numbers(valid.filter((x) => x.v.totalPayableAmount >= addressLimit && String(x.v.customerAddress || '').trim().length < 5)));

    add('pan', 'warn', 'PAN not recorded above ₹2,00,000',
        'The buyer\'s PAN must be quoted on a sale above ₹2 lakh (Income Tax Rule 114B). It is also needed for the 1% TDS shown on the invoice.',
        numbers(valid.filter((x) => x.v.totalPayableAmount > panLimit && !String(x.v.customerPan || '').trim())));

    add('pos', 'warn', 'Place of supply missing', 'Every invoice must state the place of supply: it decides CGST + SGST or IGST.',
        numbers(valid.filter((x) => !String(x.v.placeOfSupply || '').trim())));

    add('hsn', 'info', 'HSN code missing on a line', 'Report every line under an HSN code (4 digits for turnover up to ₹5 crore, 6 digits above).',
        numbers(valid.filter((x) => x.v.items.some((l) => !String(l.hsnCode || '').trim()))));

    // Cash from one buyer in one day (all invoices together): Income Tax Act s.269ST, "2 lakh or more"
    const cash = new Map();
    for (const { v } of valid) {
        const who = v.customerObjectId || v.customerMobile || '';
        if (!who) continue;
        for (const p of v.paymentHistory) {
            const pd = istYmd(p.date);
            if (p.mode !== 'Cash' || !pd || pd < from || pd > to) continue;
            const key = `${who}|${pd}`;
            const e = cash.get(key) || { total: 0, numbers: new Set() };
            e.total += p.amount; e.numbers.add(v.invoiceNumber);
            cash.set(key, e);
        }
    }
    add('cash', 'warn', 'Cash of ₹2,00,000 or more from one buyer in a day',
        'Section 269ST bars receiving ₹2 lakh or more in cash from one person in a day. The penalty equals the cash received and falls on the shop: ask your CA before filing.',
        [...new Set([...cash.values()].filter((e) => e.total >= cashLimit).flatMap((e) => [...e.numbers]))]);

    // Serial numbers must run without gaps: every number in the main series must be an invoice (issued or cancelled)
    const plain = views.filter((x) => /^\d+$/.test(String(x.v.invoiceNumber).trim())).map((x) => parseInt(x.v.invoiceNumber, 10));
    if (plain.length > 1) {
        const set = new Set(plain), lo = Math.min(...plain), hi = Math.max(...plain), missing = [];
        for (let n = lo; n <= hi && missing.length < 500; n++) if (!set.has(n)) missing.push(String(n).padStart(4, '0'));
        if (missing.length && hi - lo < 100000) add('gaps', 'info', 'Invoice numbers missing from the sequence',
            'Invoice numbers must run in an unbroken series. Each missing number should be explained (for example an invoice made in another period, or a cancelled bill kept on record).', missing);
    }

    // B2C large invoices are reported one by one (table 5): a heads-up, not a problem
    add('b2cl', 'info', 'Inter-state sales above ₹1,00,000 to unregistered buyers',
        'These are listed invoice by invoice in GSTR-1 table 5 (B2C large), not in the state summary.',
        numbers(valid.filter((x) => (x.v.gstType === 'IGST' || x.v.gstSummary.igst > 0) && x.v.totalPayableAmount > 100000)));

    // The old website rule left extra charges untaxed
    add('untaxed', 'warn', 'Extra charges billed without GST',
        'Packing, courier and similar charges are part of the taxable value (CGST Act s.15(2)(c)). These older invoices did not charge GST on them: ask your CA how to report them.',
        numbers(valid.filter((x) => x.v.discountMode !== 'before_gst' && x.v.additionalCharges > 0)));

    return out.sort((a, b) => (a.severity === b.severity ? 0 : a.severity === 'warn' ? -1 : 1));
}

// ── monthly GST invoice record (the website's "Print PDF" report) ─────────────
const RECORD_STATUSES = ['active', 'revised', 'pending', 'delivered', 'cancelled', 'void', 'deleted'];
const VALID_STATUSES = ['active', 'revised', 'pending', 'delivered'];     // the only ones that count in the totals
const invNo = (v) => { const m = /(\d+)\s*$/.exec(String(v)); return m ? parseInt(m[1], 10) : 0; };

/**
 * Everything the "GST Invoice Record" PDF needs for one calendar month, exactly as the website builds it:
 * EVERY invoice of the month is listed (cancelled / void / deleted too, marked as such, for a complete audit trail),
 * but only Active, Revised, Pending and Delivered invoices count in the financial totals.
 */
function monthlyRecord(docs, year, month) {
    const from = fmt(year, month, 1), to = fmt(year, month, lastDay(year, month));
    const list = [];
    for (const d of docs || []) {
        const v = toView(d);
        const date = (YMD.test(v.invoiceDate) ? v.invoiceDate : istYmd(v.createdAt)) || '';
        if (!date || date < from || date > to) continue;
        const status = String(v.status || '').toLowerCase();
        if (!RECORD_STATUSES.includes(status)) continue;
        list.push({ v, date, status });
    }
    list.sort((a, b) => a.date.localeCompare(b.date) || invNo(a.v.invoiceNumber) - invNo(b.v.invoiceNumber) || String(a.v.invoiceNumber).localeCompare(String(b.v.invoiceNumber)));

    const T = { count: 0, taxable: 0, additional: 0, cgst: 0, sgst: 0, igst: 0, gst: 0, amount: 0, goldWeight: 0, silverWeight: 0, discount: 0, making: 0, intraTaxable: 0, interTaxable: 0, grossWeight: 0, metalValue: 0, stone: 0, hallmark: 0, hallmarkPassedOn: 0 };
    const byMetal = new Map(), byPay = new Map(), byBranch = new Map();
    const bump = (map, key, add) => { const e = map.get(key) || { key, invoices: 0, pieces: 0, grossWt: 0, netWt: 0, taxable: 0, gst: 0, amount: 0, count: 0 }; for (const [k, v] of Object.entries(add)) e[k] += v; map.set(key, e); };
    const statusCounts = Object.fromEntries(RECORD_STATUSES.map((s) => [s, 0]));
    const invoices = list.map(({ v, date, status }) => {
        statusCounts[status]++;
        const valid = VALID_STATUSES.includes(status);
        const inter = v.gstType === 'IGST' || v.gstSummary.igst > 0;
        if (valid) {
            T.count++; T.taxable += v.gstSummary.taxableValue; T.additional += v.additionalCharges; T.cgst += v.gstSummary.cgst; T.sgst += v.gstSummary.sgst; T.igst += v.gstSummary.igst;
            T.gst += v.gstSummary.totalTax; T.amount += v.totalPayableAmount; T.discount += v.discountGiven;
            if (inter) T.interTaxable += v.gstSummary.taxableValue; else T.intraTaxable += v.gstSummary.taxableValue;
            bump(byBranch, v.branchName || 'Main branch', { invoices: 1, taxable: v.gstSummary.taxableValue, gst: v.gstSummary.totalTax, amount: v.totalPayableAmount });
            for (const l of v.items) {
                T.making += lineMaking(l);
                const m = String(l.metalType).toLowerCase();
                if (m === 'gold') T.goldWeight += l.netWt; else if (m === 'silver') T.silverWeight += l.netWt;
                T.grossWeight += l.grossWt; T.metalValue += l.netWt * l.rate; T.stone += l.stoneCharge; T.hallmark += l.hallmarkCharge; if (l.hallmarkTaxed === false) T.hallmarkPassedOn += l.hallmarkCharge;
                bump(byMetal, `${l.metalType || 'Other'}|${l.purity || ''}`, { pieces: 1, grossWt: l.grossWt, netWt: l.netWt, taxable: l.taxableAmount });
            }
            // payments: what each mode brought in (falls back to the invoice's mode when no history was kept)
            const hist = v.paymentHistory.length ? v.paymentHistory : (v.paidAmount > 0 ? [{ mode: v.paymentMode || 'Cash', amount: v.paidAmount }] : []);
            for (const p of hist) bump(byPay, p.mode || 'Cash', { count: 1, amount: p.amount });
        }
        return {
            number: v.invoiceNumber, date, delivery: v.deliveryDate, status, counted: valid, gstType: inter ? 'IGST' : 'CGST_SGST',
            customer: { name: v.customerName, mobile: v.customerMobile, address: v.customerAddress, state: v.customerState, stateCode: v.customerStateCode, pan: v.customerPan },
            reverseCharge: v.reverseCharge || 'No', tds: v.tds.applicable ? { rate: v.tds.rate, amount: v.tds.amount } : null, placeOfSupply: v.placeOfSupply, terms: v.termsOfDelivery || 'Customer Pickup',
            paymentMode: v.paymentMode || 'Cash', note: v.note, reference: v.reference,
            branch: v.branchName, createdBy: v.createdBy, createdAt: v.createdAt, source: v.source, goldRate: v.goldRate, silverRate: v.silverRate, revisionId: v.revisionId, printCount: v.printStatus,
            paid: v.paidAmount, due: v.dueAmount, advance: v.advanceAmount, payments: v.paymentHistory.map((p) => ({ mode: p.mode, amount: p.amount, date: p.date, reference: p.reference, receivedBy: p.receivedBy })),
            billBeforeDiscount: v.billBeforeDiscount, grossTaxable: v.grossTaxable,
            items: v.items.map((l) => ({
                name: l.particular, itemName: l.itemName, hsn: l.hsnCode || '7113', metal: l.metalType, purity: l.purity, code: l.productCode, huid: l.huid, certification: l.certification,
                grossWt: l.grossWt, netWt: l.netWt, rate: l.rate, metalValue: r2(l.netWt * l.rate),
                making: l.makingCharge > 0 ? l.makingCharge : lineMaking(l), makingDerived: !(l.makingCharge > 0) && lineMaking(l) > 0,
                stone: l.stoneCharge, hallmark: l.hallmarkCharge, hallmarkTaxed: l.hallmarkTaxed, extras: l.extras, discount: l.discount, amount: l.taxableAmount,
            })),
            cgst: v.gstSummary.cgst, sgst: v.gstSummary.sgst, igst: v.gstSummary.igst, taxable: v.gstSummary.taxableValue, totalGst: v.gstSummary.totalTax,
            additionalCharges: v.additionalCharges, additionalChargesGst: v.additionalChargesGst,
            hallmarkPassedOn: r2(v.items.reduce((a, l) => a + (l.hallmarkTaxed === false ? l.hallmarkCharge : 0), 0)),   // hallmark / HUID fees added after tax (rule v3): in the payable, not in the taxable value
            discount: v.discountGiven, discountBeforeGst: v.discountMode === 'before_gst', roundOff: v.roundOff, totalPayable: v.totalPayableAmount, amountInWords: v.amountInWords,
        };
    });

    // Starting / ending number follow the main series (plain numbers). Branch series like "BR2-0001" are listed apart.
    const plain = invoices.filter((i) => /^\d+$/.test(String(i.number).trim()));
    const nums = (plain.length ? plain : invoices).map((i) => invNo(i.number)).filter((n) => n > 0);
    const seriesMap = new Map();
    for (const i of invoices) {
        const mm = /^([A-Za-z][A-Za-z0-9]*)-(\d+)$/.exec(String(i.number));
        if (!mm) continue;
        const cur = seriesMap.get(mm[1]) || { name: mm[1], from: i.number, to: i.number, count: 0 };
        if (String(i.number) < cur.from) cur.from = i.number;
        if (String(i.number) > cur.to) cur.to = i.number;
        cur.count++;
        seriesMap.set(mm[1], cur);
    }
    const r = (o) => Object.fromEntries(Object.entries(o).map(([k, x]) => [k, k === 'count' ? x : (k.endsWith('Weight') ? r3(x) : r2(x))]));
    const totals = r(T);
    const pct = (n) => (totals.taxable > 0 ? r2((n / totals.taxable) * 100) : 0);
    return {
        period: { year, month, monthName: MONTHS_FULL[month - 1], from, to },
        invoices,
        totals,
        breakdown: {
            metals: [...byMetal.values()].map((e) => { const [metal, purity] = e.key.split('|'); return { metal, purity, pieces: e.pieces, grossWt: r3(e.grossWt), netWt: r3(e.netWt), taxable: r2(e.taxable) }; }).sort((a, b) => a.metal.localeCompare(b.metal) || a.purity.localeCompare(b.purity)),
            payments: [...byPay.values()].map((e) => ({ mode: e.key, count: e.count, amount: r2(e.amount) })).sort((a, b) => b.amount - a.amount),
            branches: [...byBranch.values()].map((e) => ({ branch: e.key, invoices: e.invoices, taxable: r2(e.taxable), gst: r2(e.gst), amount: r2(e.amount) })).sort((a, b) => a.branch.localeCompare(b.branch)),
        },
        tracking: {
            start: nums.length ? Math.min(...nums) : 0, end: nums.length ? Math.max(...nums) : 0, branchSeries: [...seriesMap.values()],
            total: invoices.length, valid: T.count, cancelledVoidDeleted: statusCounts.cancelled + statusCounts.void + statusCounts.deleted, statusCounts,
            avgInvoice: T.count > 0 ? r2(T.amount / T.count) : 0, gstRate: pct(totals.gst),
            // each rate is measured on the invoices it applies to (CGST/SGST on in-state sales, IGST on inter-state ones)
            cgstRate: totals.intraTaxable > 0 ? r2((totals.cgst / totals.intraTaxable) * 100) : 0, sgstRate: totals.intraTaxable > 0 ? r2((totals.sgst / totals.intraTaxable) * 100) : 0, igstRate: totals.interTaxable > 0 ? r2((totals.igst / totals.interTaxable) * 100) : 0,
        },
    };
}

module.exports = {
    complianceChecks, monthlyRecord, RECORD_STATUSES, VALID_STATUSES,
    r2, r3, parse, fmt, periodKey, periodRange, nextPeriodKey, listPeriods, dueDate, obligations, statusList, alerts, pendingReminders,
    qrmpDay3b, RETURN_TYPES, RETURN_TITLES, utilise, itcLedger, sumT, totalOf, zeroT, summarise, registerPage, liabilityOf, purchaseItc,
    istYmd, daysBetween, lineMaking, baseName, MONTHS_FULL, fyStartYear, fyLabel, HIDDEN_STATUSES,
};
