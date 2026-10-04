/**
 * seed-sample-history.js — a realistic year and a half of sales for the LOCAL test database.
 *
 *   node scripts/seed-sample-history.js          (re-run any time; it resets the local invoices first)
 *   node scripts/seed-sample-history.js --keep   (do not reset; only add missing sample records)
 *
 * What it builds (deterministic, so two runs give the same data):
 *   - Apr 2025 - Mar 2026 (FY 2025-26): invoices in the WEBSITE's shape (discount taken after GST, no purity/HUID fields),
 *     main shop only - like the real history that already exists on the live site.
 *   - Apr 2026 - today: invoices in the APP's shape (discount before GST, purity, gross/net weight, HUID, stones ...)
 *     from three shops: the main shop, "Bagbazar Showroom" (same GSTIN) and "Mumbai Branch" (its own GSTIN, so its own returns).
 *   - purchases (input tax credit), filed GSTR-1 / GSTR-3B records (some periods left open so the calendar shows
 *     "due" / "overdue"), branch staff logins.
 * Every invoice is worked out by the real billing engine, so all totals are internally consistent.
 * Customer names / mobile numbers / GSTINs here are invented. Refuses to run against anything but localhost.
 */
'use strict';

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { MongoClient, ObjectId } = require('mongodb');
const Calc = require('../services/billingCalc');
const GstStates = require('../services/gstStates');

const URI = process.env.LOCAL_MONGO || 'mongodb://127.0.0.1:27018';
if (!/(localhost|127\.0\.0\.1)/.test(URI)) { console.error('Refusing to run: local database only.'); process.exit(2); }
const KEEP = process.argv.includes('--keep');

// ── deterministic random ─────────────────────────────────────────────────────
let seed = 20260920;
const rnd = () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const between = (lo, hi) => lo + rnd() * (hi - lo);
const chance = (p) => rnd() < p;
const round10 = (n) => Math.round(n / 10) * 10;
const pad = (n, w = 2) => String(n).padStart(w, '0');
const ymd = (d) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;

const TODAY = Calc.todayIST();
const START = '2025-04-01';
const APP_FROM = '2026-04-01';                 // from here on invoices are made in the app (new shape)

// ── rates: a slow climb with day-to-day noise ────────────────────────────────
const anchors = [['2025-04-01', 8850], ['2025-08-01', 9500], ['2025-11-01', 11200], ['2026-02-01', 12400], ['2026-06-01', 13300], ['2026-10-01', 14100]];
const silverAnch = [['2025-04-01', 98], ['2025-11-01', 125], ['2026-06-01', 158], ['2026-10-01', 170]];
const lerp = (list, date) => {
    const t = Date.parse(date);
    for (let i = 0; i < list.length - 1; i++) {
        const a = Date.parse(list[i][0]), b = Date.parse(list[i + 1][0]);
        if (t <= b) return list[i][1] + ((list[i + 1][1] - list[i][1]) * Math.max(0, t - a)) / (b - a);
    }
    return list[list.length - 1][1];
};
const goldRate = (date) => Math.round(lerp(anchors, date) + between(-60, 60));
const silverRate = (date) => Math.round((lerp(silverAnch, date) + between(-2, 2)) * 10) / 10;

// ── catalogue ────────────────────────────────────────────────────────────────
const GOLD = [
    ['Gold Ring', 2, 6, 0.09, 0.14, 26], ['Gold Chain', 4, 16, 0.05, 0.09, 22], ['Gold Bangle', 8, 24, 0.05, 0.09, 12], ['Gold Earring', 1.5, 6, 0.09, 0.15, 24],
    ['Gold Necklace', 10, 36, 0.06, 0.11, 8], ['Gold Pendant', 1, 5, 0.09, 0.14, 12], ['Gold Bracelet', 8, 22, 0.06, 0.10, 6], ['Gold Nose Pin', 0.3, 1, 0.12, 0.2, 6],
    ['Gold Mangalsutra', 8, 30, 0.06, 0.1, 6], ['Gold Jhumka', 4, 14, 0.08, 0.13, 10], ['Gold Chur', 10, 24, 0.05, 0.08, 4], ['Gold Coin', 2, 10, 0.02, 0.03, 4],
];
const SILVER = [['Silver Payal', 40, 120, 0.07, 0.12, 20], ['Silver Pooja Thali', 100, 300, 0.05, 0.09, 6], ['Silver Coin', 10, 50, 0.03, 0.05, 10], ['Silver Bowl Set', 80, 250, 0.05, 0.08, 6], ['Silver Chain', 15, 45, 0.07, 0.11, 8], ['Silver Bichhiya', 6, 16, 0.08, 0.13, 8], ['Silver Idol', 60, 240, 0.05, 0.09, 4]];
const PURITIES = [['22K', 1, 0.64], ['18K', 0.818, 0.14], ['24K', 1.09, 0.06], ['22K', 1, 0.16]];
const STONES = [['Stone', 'Ruby', 1400], ['Stone', 'Emerald', 1900], ['Pearl', 'Pearl', 900], ['Diamond', 'Diamond', 5200], ['Stone', 'Kundan', 600], ['Stone', 'Coral', 700], ['Stone', 'Cubic Zirconia', 300]];
const CODE = { Ring: 'RG', Chain: 'CH', Bangle: 'BG', Earring: 'ER', Necklace: 'NK', Pendant: 'PD', Bracelet: 'BR', 'Nose Pin': 'NP', Mangalsutra: 'MS', Jhumka: 'JH', Chur: 'CR', Coin: 'CN', Payal: 'PY', 'Pooja Thali': 'PT', 'Bowl Set': 'BS', Bichhiya: 'BC', Idol: 'ID' };
const HUID_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
const huid = () => Array.from({ length: 6 }, () => HUID_CHARS[Math.floor(rnd() * HUID_CHARS.length)]).join('');
const weighted = (list) => { let t = list.reduce((a, x) => a + x[x.length - 1], 0) * rnd(); for (const x of list) { t -= x[x.length - 1]; if (t <= 0) return x; } return list[0]; };

// ── people (invented) ────────────────────────────────────────────────────────
const FIRST = ['Subrata', 'Anita', 'Debasis', 'Mousumi', 'Rajesh', 'Sunita', 'Partha', 'Kakoli', 'Sourav', 'Rina', 'Tapan', 'Mitali', 'Arup', 'Sikha', 'Biswajit', 'Papiya', 'Gautam', 'Namita', 'Sudip', 'Bharati', 'Amit', 'Pooja', 'Manoj', 'Rekha', 'Nirmal', 'Sandhya', 'Kartik', 'Jharna', 'Prabir', 'Shefali', 'Ashok', 'Moumita', 'Dipak', 'Lakshmi', 'Swapan', 'Chandana', 'Ratan', 'Purnima', 'Sanjay', 'Tanushree', 'Bikash', 'Madhabi', 'Ranjit', 'Ruma', 'Pradip', 'Sabita', 'Utpal', 'Krishna'];
const LAST = ['Ghosh', 'Das', 'Banerjee', 'Chatterjee', 'Mukherjee', 'Dey', 'Saha', 'Pal', 'Roy', 'Bose', 'Dutta', 'Sarkar', 'Mondal', 'Biswas', 'Bhattacharya', 'Nandi', 'Kundu', 'Chakraborty', 'Sen', 'Paul', 'Shaw', 'Gupta', 'Agarwal', 'Jaiswal', 'Sharma'];
const LOCALITY = ['Bagbazar, Chandannagar', 'Gondalpara, Chandannagar', 'Strand Road, Chandannagar', 'Khalisani, Chandannagar', 'Chinsurah, Hooghly', 'Bandel, Hooghly', 'Bansberia, Hooghly', 'Serampore, Hooghly', 'Bhadreswar, Hooghly', 'Champdani, Hooghly', 'Uttarpara, Hooghly', 'Barrackpore, North 24 Parganas', 'Shyambazar, Kolkata', 'Baranagar, Kolkata', 'Howrah Maidan, Howrah', 'Konnagar, Hooghly', 'Rishra, Hooghly', 'Tarakeswar, Hooghly'];
const MUMBAI_LOC = ['Zaveri Bazaar, Mumbai', 'Andheri West, Mumbai', 'Dadar East, Mumbai', 'Borivali, Mumbai', 'Thane West, Thane', 'Vashi, Navi Mumbai', 'Kalyan, Thane', 'Ghatkopar, Mumbai'];
const OTHER_STATES = [['07', 'Delhi'], ['10', 'Bihar'], ['20', 'Jharkhand'], ['21', 'Odisha'], ['09', 'Uttar Pradesh'], ['24', 'Gujarat'], ['29', 'Karnataka'], ['08', 'Rajasthan']];
const PAN4 = ['ABCP', 'AKFP', 'BQRP', 'CGHP', 'DFKP', 'EJLP', 'FMNP', 'GTSP', 'HRDP', 'JLBP'];
let mobileSeq = 0;
const mkCustomers = (n, mumbai = false) => Array.from({ length: n }, (_, i) => {
    const name = `${pick(FIRST)} ${pick(LAST)}`;
    mobileSeq += 1;
    const mobile = `${pick(['98', '97', '96', '90', '89', '79', '70'])}${pad(Math.floor(rnd() * 1e8), 8)}`;
    const house = 1 + Math.floor(rnd() * 180);
    return {
        name, mobile, address: `${house}/${1 + Math.floor(rnd() * 12)}, ${pick(mumbai ? MUMBAI_LOC : LOCALITY)}`,
        pan: `${pick(PAN4)}${String.fromCharCode(65 + Math.floor(rnd() * 26))}${pad(Math.floor(rnd() * 9999), 4)}${String.fromCharCode(65 + Math.floor(rnd() * 26))}`,
        regular: i < n * 0.55, other: chance(0.07) ? pick(OTHER_STATES) : null,
    };
});

// ── shops ────────────────────────────────────────────────────────────────────
const SHOPS = [
    { id: 'main', name: 'Main branch', prefix: '', state: '19', stateName: 'West Bengal', gstin: '19AKFPN3465R1ZB', from: START, perMonth: 34, customers: mkCustomers(110) },
    { id: null, key: 'bagbazar', name: 'Bagbazar Showroom', prefix: 'BGB', state: '19', stateName: 'West Bengal', gstin: '19AKFPN3465R1ZB', ownGstin: '', city: 'Kolkata', from: APP_FROM, perMonth: 15, customers: mkCustomers(60) },
    { id: null, key: 'mumbai', name: 'Mumbai Branch', prefix: 'MUM', state: '27', stateName: 'Maharashtra', gstin: '27AKFPN3465R1ZE', ownGstin: '27AKFPN3465R1ZE', city: 'Mumbai', from: '2026-06-01', perMonth: 9, customers: mkCustomers(40, true) },
];
// festive / wedding seasons: Akshaya Tritiya (Apr-May), wedding (Jan-Feb, Nov-Dec), Dhanteras + Diwali (Oct-Nov)
const SEASON = { 1: 1.25, 2: 1.2, 3: 0.9, 4: 1.35, 5: 1.2, 6: 0.85, 7: 0.7, 8: 0.75, 9: 0.95, 10: 1.7, 11: 1.5, 12: 1.25 };

function makeItems(date, legacy, silverShare = 0.18) {
    const n = chance(0.7) ? 1 : chance(0.75) ? 2 : chance(0.7) ? 3 : 4;
    const g = goldRate(date), s = silverRate(date);
    const items = [];
    for (let i = 0; i < n; i++) {
        const silver = chance(silverShare);
        const [title, lo, hi, mLo, mHi] = silver ? weighted(SILVER) : weighted(GOLD);
        const base = title.replace(/^(Gold|Silver) /, '');
        const [purity, factor] = silver ? ['925', 0.94] : weighted(PURITIES);
        const rate = Math.round((silver ? s : g) * factor);
        const netWt = Math.round(between(lo, hi) * 100) / 100;
        const gross = Math.round((netWt + (silver ? 0 : between(0, 0.35))) * 1000) / 1000;
        let making = round10(netWt * rate * between(mLo, mHi));
        const it = { particulars: title, metalType: silver ? 'Silver' : 'Gold', netWt, rate, makingCharge: making, hsnCode: '7113' };
        if (!legacy) {
            it.purity = silver ? '925' : purity;
            it.grossWt = gross;
            it.productCode = `LGP-${CODE[base] || 'OT'}-${pad(Math.floor(rnd() * 9000) + 100, 4)}`;
            it.itemName = title;
            if (!silver && netWt >= 1 && chance(0.85)) { it.certification = 'huid'; it.huid = huid(); it.hallmarkCharge = 45; }
            if (!silver && chance(0.16)) {
                const extras = [];
                const k = chance(0.25) ? 2 : 1;
                for (let e = 0; e < k; e++) { const [kind, name, price] = pick(STONES); extras.push({ kind, name, weight: Math.round(between(0.1, 1.2) * 100) / 100, amount: round10(price * between(0.6, 2.2)) }); }
                it.extras = extras;
            }
        } else if (!silver && netWt >= 1 && chance(0.8)) {
            // the website writes the HUID into the name and folds the hallmark fee into the making charge
            it.particulars = `${title} (HUID: ${huid()})`;
            it.makingCharge = making + 45;
        }
        items.push(it);
    }
    return { items, g, s };
}

function buildInvoice({ shop, number, date, customer, legacy, cashByDay }) {
    const { items, g, s } = makeItems(date, legacy, shop.state === '27' ? 0.08 : 0.18);
    const inter = shop.state === '27' ? !chance(0.9) : !!customer.other;
    const place = inter ? (shop.state === '27' ? (chance(0.5) ? ['24', 'Gujarat'] : ['29', 'Karnataka']) : customer.other) : [shop.state, shop.stateName];
    const placeStr = `${place[0]}-${place[1]}`;
    const extra = chance(0.06) ? pick([50, 100, 150, 200, 350]) : 0;                       // packing / courier
    // first pass: the bill without discount
    let calc = Calc.computeInvoice({ items, goldRate: g, silverRate: s, interstate: inter, additionalCharges: extra, discount: 0, paidAmount: 0, discountMode: legacy ? 'after_gst' : undefined });
    if (!calc.ok) return null;
    // a discount that makes the payable a round number, on about 45% of bills (the staff habit the site records)
    let discount = 0;
    const bill = calc.billBeforeDiscount || calc.totalAmount;
    if (chance(0.45)) {
        const target = bill >= 20000 ? Math.floor(bill / 100) * 100 : Math.floor(bill / 10) * 10;
        const d = Math.round(bill - target);
        if (d > 0 && d < bill * 0.04) discount = d;
    }
    if (discount) {
        const c2 = Calc.computeInvoice({ items, goldRate: g, silverRate: s, interstate: inter, additionalCharges: extra, discount, paidAmount: 0, discountMode: legacy ? 'after_gst' : undefined });
        if (c2.ok) calc = c2; else discount = 0;
    }
    const payable = calc.totalPayableAmount;

    // payments: cash / online / card, sometimes split, regulars sometimes leave a balance
    const partial = customer.regular && payable > 15000 && chance(0.16);
    let paidTotal = partial ? Math.round(payable * between(0.4, 0.8) / 100) * 100 : payable;
    const cashKey = `${customer.mobile}|${date}`;
    const cashSoFar = cashByDay.get(cashKey) || 0;
    const cashRoom = Math.max(0, 190000 - cashSoFar);
    const pays = [];
    const modeOnce = () => pick(['Cash', 'Cash', 'Cash', 'Online', 'Online', 'Card']);
    if (paidTotal > 150000 || (paidTotal > 60000 && chance(0.55))) {
        const cash = Math.min(cashRoom, round10(paidTotal * between(0.15, 0.4)));
        if (cash > 0) pays.push({ amount: cash, mode: 'Cash' });
        pays.push({ amount: Math.round((paidTotal - (cash > 0 ? cash : 0)) * 100) / 100, mode: pick(['Online', 'Card', 'Cheque']) });
    } else {
        let mode = modeOnce();
        if (mode === 'Cash' && paidTotal > cashRoom) mode = 'Online';
        pays.push({ amount: paidTotal, mode });
    }
    for (const p of pays) if (p.mode === 'Cash') cashByDay.set(cashKey, (cashByDay.get(cashKey) || 0) + p.amount);
    const hh = pad(10 + Math.floor(rnd() * 9)), mm = pad(Math.floor(rnd() * 60)), ss = pad(Math.floor(rnd() * 60));
    const when = new Date(`${date}T${hh}:${mm}:${ss}+05:30`);
    const ref = (mode) => (mode === 'Online' ? `UPI${Math.floor(rnd() * 9e11 + 1e11)}` : mode === 'Card' ? `CARD${Math.floor(rnd() * 9e5 + 1e5)}` : mode === 'Cheque' ? `CHQ${Math.floor(rnd() * 9e5 + 1e5)}` : '');
    const staff = pick(shop.staff);
    const history = pays.map((p, i) => ({
        amount: p.amount, payment_mode: p.mode, transaction_reference: ref(p.mode) || `Initial payment with invoice #${number}`,
        description: 'Payment at the time of invoice creation', payment_date: date, payment_time: `${hh}:${mm}:${pad(Number(ss) + i)}`,
        created_at: when, created_by: null, files: [], ...(legacy ? {} : { request_id: `sample:${number}:${i}`, created_by_name: staff, source: 'app' }),
    }));
    // a balance is often cleared a few weeks later
    const dueLeft = Math.round((payable - paidTotal) * 100) / 100;
    let paidFinal = paidTotal;
    if (dueLeft > 0 && chance(0.6)) {
        const later = new Date(Date.parse(`${date}T12:00:00Z`) + Math.floor(between(6, 40)) * 86400000);
        if (ymd(later) < TODAY) {
            const lk = `${customer.mobile}|${ymd(later)}`;
            let mode = pick(['Cash', 'Online']);
            if (mode === 'Cash' && (cashByDay.get(lk) || 0) + dueLeft >= 190000) mode = 'Online';
            if (mode === 'Cash') cashByDay.set(lk, (cashByDay.get(lk) || 0) + dueLeft);
            history.push({ amount: dueLeft, payment_mode: mode, transaction_reference: ref(mode) || 'Balance received', description: 'Balance payment', payment_date: ymd(later), payment_time: '16:20:05', created_at: new Date(`${ymd(later)}T10:50:05Z`), created_by: null, files: [], ...(legacy ? {} : { request_id: `sample:${number}:b`, created_by_name: staff, source: 'app' }) });
            paidFinal = payable;
        }
    }
    const delivery = date;
    const status = paidFinal >= payable ? 'delivered' : 'active';
    const doc = {
        invoice_number: number, invoice_date: date, customer_name: customer.name, customer_address: customer.address, customer_mobile: customer.mobile,
        customer_id: '', customer_pan: calc.tdsApplicable || payable >= 200000 ? customer.pan : (chance(0.25) ? customer.pan : ''),
        customer_state: place[1], customer_state_code: place[0], place_of_supply: placeStr, reverse_charge: 'No', terms_of_delivery: 'Customer Pickup',
        reference: '', lgp_wallet: 0, delivery_date: delivery, gold_rate: g, silver_rate: s, items: calc.items,
        additional_charges: calc.additionalCharges, ...(legacy ? {} : { additional_charges_gst: calc.additionalGst }),
        total_amount: calc.totalAmount, discount: calc.discount, round_off: calc.roundOff,
        note: chance(0.08) ? pick(['Old ornament exchanged', 'Regular customer - festival offer', 'Making charge waived on request', 'Delivery after polishing']) : '',
        total_payable_amount: payable, amount_in_words: Calc.amountInWords(payable).combined, paid_amount: paidFinal, payment_mode: pays.slice().sort((x, y) => y.amount - x.amount)[0].mode,
        due_advance: Math.round((paidFinal - payable) * 100) / 100, tds_applicable: calc.tdsApplicable, tds_rate: calc.tdsRate, tds_amount: calc.tdsAmount,
        gst_summary: calc.gstSummary, created_at: when, status, print_status: chance(0.7) ? 1 : 0, pay_no: history.length, payment_history: history,
        sample_history: true,
    };
    if (!legacy) {
        Object.assign(doc, {
            walk_in: !customer.regular, branch_id: shop.id, branch_name: shop.name, created_by_name: staff, request_id: `sample:${number}`, calc_rule: calc.rule, source: 'app',
            gst_type: calc.gstType, supply_state_code: shop.state, seller_gstin: shop.gstin, discount_mode: calc.discountMode, discount_given: calc.discountGiven,
            discount_before_gst: calc.discountBeforeGst, gross_taxable: calc.grossTaxable, bill_before_discount: calc.billBeforeDiscount, metal_value: calc.metalValue,
        });
    } else {
        doc.due_advance = Math.round((paidFinal - payable) * 100) / 100;
    }
    // occasional non-standard states
    const r = rnd();
    if (r < 0.014) doc.status = 'cancelled';
    else if (r < 0.017) doc.status = 'void';
    else if (r < 0.026) doc.status = 'revised';
    return doc;
}

async function main() {
    const client = await MongoClient.connect(URI);
    const mongoose = require('mongoose');
    await mongoose.connect(`${URI}/lgp_dev`);   // ONE database: the website's, with the app's collections in it
    const Branch = require('../models/Branch');
    const User = require('../models/User');
    const lgp = client.db('lgp_dev');
    const shopmanage = client.db('lgp_dev');
    const app = client.db('lgp_dev');

    // leftovers of the automated tests (api-smoke.js) do not belong in a realistic shop
    await app.collection('app_branches').deleteMany({ name: /^SMOKE/ });
    await app.collection('users').deleteMany({ full_name: /^SMOKE/ });

    // branches + their staff logins
    const staffOf = {};
    for (const shop of SHOPS.slice(1)) {
        let b = await Branch.findOne({ name: shop.name });
        if (!b) b = await Branch.create({ name: shop.name, code: shop.prefix, invoicePrefix: shop.prefix, city: shop.city, state: shop.stateName, gstin: shop.ownGstin || '', address: `${shop.city}` });
        else { b.gstin = shop.ownGstin || ''; b.invoicePrefix = shop.prefix; b.state = shop.stateName; await b.save(); }
        shop.id = String(b._id);
    }
    SHOPS[0].staff = ['Admin'];
    const staffLogins = [['9000000011', 'Bagbazar Staff', SHOPS[1]], ['9000000012', 'Mumbai Staff', SHOPS[2]], ['9000000013', 'Main Counter Staff', SHOPS[0]]];
    for (const [mobile, name, shop] of staffLogins) {
        let u = await User.findOne({ mobile });
        if (!u) u = await User.create(User.forCreate({ name, mobile, password: 'Staff@123', role: 'staff', branchId: shop.id, branchName: shop.name }));
        else { u.branchId = shop.id; u.branchName = shop.name; await u.save(); }
        shop.staff = [name === 'Main Counter Staff' ? 'Admin' : name, name];
    }
    SHOPS[0].staff = ['Admin', 'Main Counter Staff'];

    if (!KEEP) {
        await lgp.collection('invoices').deleteMany({});
        await lgp.collection('shop_info').deleteMany({});
        await shopmanage.collection('purchases').deleteMany({ sample_history: true });
        await client.db('lgp_dev').collection('gst_data').deleteMany({ sample_history: true });
    }

    // invoices, month by month
    const docs = [];
    const counters = { main: 1299 };
    const cashByDay = new Map();
    let d = new Date(`${START}T00:00:00Z`);
    const end = new Date(`${TODAY}T00:00:00Z`);
    const monthTotals = new Map();
    for (; d <= end; d = new Date(d.getTime() + 86400000)) {
        const date = ymd(d);
        const dow = d.getUTCDay();
        const [y, m, dd] = date.split('-').map(Number);
        const dim = new Date(Date.UTC(y, m, 0)).getUTCDate();
        for (const shop of SHOPS) {
            if (date < shop.from) continue;
            const legacy = date < APP_FROM;
            // average per open day with the season and weekday (Sunday quiet, Saturday busy), plus a Dhanteras-like burst
            let perDay = (shop.perMonth * SEASON[m]) / (dim - 4);
            if (dow === 0) perDay *= 0.25; else if (dow === 6) perDay *= 1.35; else if (dow === 5) perDay *= 1.1;
            if (m === 10 && dd >= 17 && dd <= 21) perDay *= 2.6;
            let n = Math.floor(perDay);
            if (rnd() < perDay - n) n++;
            for (let i = 0; i < n; i++) {
                const key = shop.id;
                counters[key] = (counters[key] || (shop.id === 'main' ? 1299 : 0)) + 1;
                const number = shop.prefix ? `${shop.prefix}-${pad(counters[key], 4)}` : pad(counters[key], 4);
                const customer = pick(shop.customers);
                const doc = buildInvoice({ shop, number, date, customer, legacy, cashByDay });
                if (!doc) { counters[key]--; continue; }
                docs.push(doc);
                const mk = `${shop.name}|${date.slice(0, 7)}`;
                monthTotals.set(mk, (monthTotals.get(mk) || 0) + 1);
            }
        }
    }
    if (docs.length) await lgp.collection('invoices').insertMany(docs, { ordered: false });
    // the numbering documents continue where the sample stops
    await lgp.collection('shop_info').updateOne({ shop_id: 'default' }, { $set: { last_invoice_number: counters.main, updated_at: new Date() }, $setOnInsert: { shop_id: 'default', created_at: new Date() } }, { upsert: true });
    for (const shop of SHOPS.slice(1)) {
        await lgp.collection('shop_info').updateOne({ shop_id: `branch:${shop.id}` }, { $set: { last_invoice_number: counters[shop.id] || 0, updated_at: new Date() }, $setOnInsert: { shop_id: `branch:${shop.id}`, created_at: new Date() } }, { upsert: true });
    }

    // purchases (input tax credit): a few supplier bills a month for each registration
    const purchases = [];
    const SUP = [['Kolkata Bullion House', '19AAECK5521M1ZP'], ['Bowbazar Gold Suppliers', '19AABFB2210L1Z8'], ['Shree Karigar Jewels', '19AGHPS7745Q1ZK'], ['Rajlaxmi Silver Works', '19AAGFR8842D1Z3'], ['Jaipur Kundan Exports', '08AAKFJ3311N1ZC']];
    let pn = 0;
    for (let y = 2025, m = 4; `${y}-${pad(m)}` <= TODAY.slice(0, 7); m === 12 ? (y++, m = 1) : m++) {
        for (const shop of SHOPS) {
            if (`${y}-${pad(m)}-28` < shop.from) continue;
            const k = shop.id === 'main' ? 2 + Math.floor(rnd() * 2) : 1;
            for (let i = 0; i < k; i++) {
                const day = 2 + Math.floor(rnd() * 24);
                const date = `${y}-${pad(m)}-${pad(day)}`;
                if (date > TODAY) continue;
                const [name, gstin] = shop.state === '27' ? ['Zaveri Gold Traders', '27AABCZ4410F1ZR'] : pick(SUP);
                const silver = chance(0.25);
                const qty = Math.round(between(silver ? 500 : 60, silver ? 2500 : 420) * 1000) / 1000;
                const rate = silver ? silverRate(date) : Math.round(goldRate(date) * 0.985);
                const amt = Math.round(qty * rate * 100) / 100;
                const same = gstin.slice(0, 2) === shop.state;
                const gst = Math.round(amt * 0.03 * 100) / 100;
                const half = Math.round(gst * 50) / 100;
                pn++;
                const made = new Date(`${date}T06:00:00Z`);
                const stamp = `${date} 11:30:00`;
                purchases.push({
                    // the website's own fields (the one shared `purchases` collection: see models/Purchase.js)
                    invoice_date: date, invoice_number: `SUP/${y}/${pad(m)}/${pad(pn, 4)}`, metal_type: silver ? 'Silver' : 'Gold', biller: name, description: silver ? 'SILVER BAR' : 'GOLD BAR (99.50%)',
                    quantity: qty, rate, total_amount: Math.round((amt + gst) * 100) / 100,
                    created_at: made, created_ist: stamp, created_by: 'seed', created_by_name: 'Sample', updated_at: made, updated_ist: stamp, updated_by: 'seed', updated_by_name: 'Sample',
                    // what only the app records
                    totalAmount: amt, gstRate: 3, cgstAmount: same ? half : 0, sgstAmount: same ? half : 0, igstAmount: same ? 0 : gst, totalGst: gst,
                    transactionType: same ? 'intra-state' : 'inter-state', hsnCode: '7113', billerGstin: gstin, itcCgst: same ? half : 0, itcSgst: same ? half : 0, itcIgst: same ? 0 : gst, totalItc: gst,
                    effectiveCost: amt, totalPayable: Math.round((amt + gst) * 100) / 100, netPayable: Math.round((amt + gst) * 100) / 100, roundOff: 0, branchId: shop.id, source: 'app', sample_history: true,
                });
            }
        }
    }
    if (purchases.length) await shopmanage.collection('purchases').insertMany(purchases, { ordered: false });

    // filed returns: monthly for the default GSTIN up to two months ago (last month left open), quarterly-ish for Mumbai
    const G = require('../services/gstReports');
    const gs = client.db('lgp_dev').collection('invoices');
    const filings = [];
    const reg = { def: SHOPS[0].id, ids: ['main', SHOPS[1].id], gstin: '' };
    const sumFor = async (ids, from, to) => {
        const rows = await gs.find({ branch_id: { $in: ids }, invoice_date: { $gte: from, $lte: to } }).toArray();
        const own = ids.includes('main') ? await gs.find({ branch_id: { $exists: false }, invoice_date: { $gte: from, $lte: to } }).toArray() : [];
        const s = G.summarise([...rows, ...own], { from, to, group: 'month' });
        return G.liabilityOf(s);
    };
    const nowKey = TODAY.slice(0, 7);
    const prevKey = (k, back) => { let [y, m] = k.split('-').map(Number); m -= back; while (m < 1) { m += 12; y--; } return `${y}-${pad(m)}`; };
    for (let y = 2025, m = 4; `${y}-${pad(m)}` <= prevKey(nowKey, 2); m === 12 ? (y++, m = 1) : m++) {
        const key = `${y}-${pad(m)}`;
        const p = G.periodRange(key);
        const lia = await sumFor(reg.ids, p.from, p.to);
        const total = Math.round(((lia.igst || 0) + (lia.cgst || 0) + (lia.sgst || 0)) * 100) / 100;
        const nm = m === 12 ? { y: y + 1, m: 1 } : { y, m: m + 1 };
        const late = chance(0.1);
        filings.push({ gstin: '', returnType: 'GSTR-1', period: key, filedOn: `${nm.y}-${pad(nm.m)}-${pad(late ? 13 : 8 + Math.floor(rnd() * 3))}`, arn: `AA19${pad(y % 100)}${pad(m)}${pad(Math.floor(rnd() * 9e6), 7)}`.toUpperCase(), taxLiability: total, itcUsed: 0, cashPaid: 0, lateFee: late ? 50 : 0, interest: 0, nil: false, note: '', sample_history: true, createdByName: 'Admin', createdAt: new Date(), updatedAt: new Date() });
        filings.push({ gstin: '', returnType: 'GSTR-3B', period: key, filedOn: `${nm.y}-${pad(nm.m)}-${pad(17 + Math.floor(rnd() * 4))}`, arn: `AA19${pad(y % 100)}${pad(m)}${pad(Math.floor(rnd() * 9e6), 7)}`.toUpperCase(), taxLiability: total, itcUsed: Math.round(total * between(0.35, 0.7) * 100) / 100, cashPaid: 0, lateFee: 0, interest: 0, nil: false, note: '', sample_history: true, createdByName: 'Admin', createdAt: new Date(), updatedAt: new Date() });
    }
    // the Mumbai registration files quarterly (QRMP): Q1 (Apr-Jun 2026) is done, Q2 is not due yet
    const mumbai = SHOPS[2];
    const q1 = await sumFor([mumbai.id], '2026-04-01', '2026-06-30');
    const q1tax = Math.round(((q1.igst || 0) + (q1.cgst || 0) + (q1.sgst || 0)) * 100) / 100;
    const base = { gstin: mumbai.ownGstin, sample_history: true, createdByName: 'Admin', nil: false, note: '', interest: 0, lateFee: 0, createdAt: new Date(), updatedAt: new Date() };
    filings.push({ ...base, returnType: 'GSTR-1', period: '2026-Q1', filedOn: '2026-07-11', arn: 'AA2707260041872', taxLiability: q1tax, itcUsed: 0, cashPaid: 0 });
    filings.push({ ...base, returnType: 'GSTR-3B', period: '2026-Q1', filedOn: '2026-07-21', arn: 'AA2707260058113', taxLiability: q1tax, itcUsed: 0, cashPaid: q1tax });
    filings.push({ ...base, returnType: 'PMT-06', period: '2026-07', filedOn: '2026-08-23', arn: 'AA2708260012204', taxLiability: 0, itcUsed: 0, cashPaid: 0 });
    for (const f of filings) f.cashPaid = Math.max(0, Math.round((f.taxLiability - f.itcUsed) * 100) / 100);
    // filed returns are kept in the website's own `gst_data` (one document per quarter), the same way the app records them
    const Filings = require('../services/gstFilings');
    const gstDb = client.db('lgp_dev');
    await gstDb.collection('gst_data').deleteMany({ sample_history: true });
    for (const f of filings) {
        const { sample_history, createdAt, updatedAt, ...rest } = f;
        await Filings.create({ ...rest, createdBy: '', createdByName: 'Admin' }, { db: gstDb, extra: { sample_history: true } }).catch((e) => console.log('filing:', f.returnType, f.period, e.message));
    }

    // settings: follow the year from April 2025, opening credit as carried from the previous year
    await app.collection('app_gst_settings').updateOne({ key: 'main' }, { $set: { key: 'main', frequency: 'monthly', trackFrom: '2025-04', remindersFrom: '2025-04', openingItc: { igst: 0, cgst: 12500, sgst: 12500 } } }, { upsert: true });
    await app.collection('app_gst_settings').updateOne({ key: `gstin:${SHOPS[2].ownGstin}` }, { $set: { key: `gstin:${SHOPS[2].ownGstin}`, frequency: 'quarterly', trackFrom: '2026-06', remindersFrom: '2026-06', openingItc: { igst: 0, cgst: 0, sgst: 0 } } }, { upsert: true });

    // stock in hand for each shop: a few boxes and tagged pieces (each shop sees only its own)
    const Item = require('../models/Item');
    const Container = require('../models/Container');
    await Item.deleteMany({ barcode: /^SMP-/ });
    await Container.deleteMany({ qrCode: /^SMP-C/ });
    let stockN = 0;
    for (const shop of SHOPS) {
        const want = shop.id === 'main' ? 30 : shop.key === 'bagbazar' ? 20 : 12;
        const boxes = [];
        for (const [i, nm] of ['Showcase A - Rings', 'Showcase B - Chains and Bangles', 'Locker - Heavy sets'].entries()) {
            boxes.push(await Container.create({ name: `${shop.name.split(' ')[0]} ${nm}`, type: 'box', capacity: 40, weightCategory: ['Light', 'Medium', 'Heavy'][i], layoutType: 'grid', qrCode: `SMP-C-${shop.prefix || 'MAIN'}-${i + 1}`, allowedItemTypes: [], branchId: shop.id }));
        }
        for (let n = 0; n < want; n++) {
            const silver = chance(0.15);
            const [title, lo, hi] = silver ? weighted(SILVER) : weighted(GOLD);
            const netWeight = Math.round(between(lo, hi) * 100) / 100;
            await Item.create({
                barcode: `SMP-${shop.prefix || 'MAIN'}-${pad(n + 1, 4)}`, name: title, itemType: title.replace(/^(Gold|Silver) /, '').toLowerCase().replace(/ /g, '_'), metalType: silver ? 'silver' : 'gold',
                purity: silver ? '925' : pick(['22k', '22k', '18k', '24k']), netWeight, grossWeight: Math.round((netWeight + between(0, 0.3)) * 1000) / 1000, branchId: shop.id,
                ...(chance(0.7) ? { containerId: boxes[Math.min(2, Math.floor(netWeight / 25))]._id } : {}),
            }).then(() => { stockN++; }).catch((e) => { if (stockN === 0 && n === 0) console.log('item seed:', e.message); });
        }
    }
    console.log(`Stock: ${stockN} items in ${SHOPS.length * 3} boxes, per shop`);

    // summary
    const byShop = {};
    for (const x of docs) byShop[x.branch_name || 'Main branch (website era)'] = (byShop[x.branch_name || 'Main branch (website era)'] || 0) + 1;
    console.log(`Invoices: ${docs.length}  ${JSON.stringify(byShop)}`);
    console.log(`Purchases: ${purchases.length}   Filed returns: ${filings.length}`);
    console.log('Branch logins (password Staff@123): 9000000011 Bagbazar, 9000000012 Mumbai, 9000000013 Main counter');
    console.log(`Main series now at ${pad(counters.main, 4)}; ${SHOPS[1].prefix}-${pad(counters[SHOPS[1].id] || 0, 4)}; ${SHOPS[2].prefix}-${pad(counters[SHOPS[2].id] || 0, 4)}`);
    console.log(`Mumbai GSTIN ${SHOPS[2].ownGstin} (own returns, quarterly). Re-run this script after api-smoke.js (the smoke test resets local invoices).`);
    await mongoose.disconnect();
    await client.close();
}

main().catch((e) => { console.error(e); process.exit(1); });
