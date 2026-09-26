/**
 * migrate-lgpadmin-customers.js — copy customers from the LGPAdmin website
 * database into the app's customer structure. See docs/customer-migration.md.
 *
 *   SOURCE_URI=... SOURCE_DB=clusterlgpadmin TARGET_URI=... node scripts/migrate-lgpadmin-customers.js [flags]
 *
 * Flags:
 *   --apply          actually write (default is a dry run: read-only, nothing written)
 *   --limit N        only look at the first N source customers
 *   --branch <id>    branch to file them under (default: main)
 *   --report <file>  write the full JSON report to a file
 *   --allow-remote   permit --apply against a non-localhost target (production!)
 *
 * Safety: the SOURCE is only ever read. The TARGET only ever receives inserts.
 * Nothing is updated or deleted anywhere. Safe to re-run (idempotent on
 * customerCode).
 */
'use strict';

const fs = require('fs');
const crypto = require('crypto');
const { MongoClient, ObjectId } = require('mongodb');
const V = require('../utils/directoryValidators');

const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };

const APPLY = flag('--apply');
const LIMIT = parseInt(opt('--limit'), 10) || 0;
const BRANCH = opt('--branch') || 'main';
const REPORT = opt('--report');

const { SOURCE_URI, TARGET_URI } = process.env;
const SOURCE_DB = process.env.SOURCE_DB || 'clusterlgpadmin';
if (!SOURCE_URI || !TARGET_URI) {
    console.error('Set SOURCE_URI and TARGET_URI (target URI must include the database name).');
    process.exit(2);
}
const isLocal = (u) => /@?(localhost|127\.0\.0\.1)(:|\/|$)/.test(u);
if (APPLY && !isLocal(TARGET_URI) && !flag('--allow-remote')) {
    console.error('Refusing to --apply to a non-local target without --allow-remote. Take a backup first.');
    process.exit(2);
}

// The website stores htmlspecialchars()-escaped text; undo it.
const decode = (v) => (typeof v !== 'string' ? v : v
    .replace(/&#0?39;|&apos;/g, "'").replace(/&quot;/g, '"')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').trim());

const ymd = (d) => `${String(d.getFullYear()).slice(2)}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;

(async () => {
    const src = new MongoClient(SOURCE_URI);
    const tgt = new MongoClient(TARGET_URI);
    await Promise.all([src.connect(), tgt.connect()]);
    const sdb = src.db(SOURCE_DB);
    const tdb = tgt.db();                       // database named in TARGET_URI
    const custs = tdb.collection('customers');
    const profs = tdb.collection('app_customer_profiles');
    const fins = tdb.collection('app_customer_finance');

    // Everything already in the target, for idempotency + duplicate detection.
    const codes = new Set((await profs.find({}, { projection: { customerCode: 1 } }).toArray()).map((p) => p.customerCode));
    const phones = new Map(); // number -> label of who owns it (name or code)
    const nameOfPhone = new Map(); // number -> customer name (for referral links)
    for (const c of await custs.find({ is_deleted: { $ne: true } }, { projection: { customer_name: 1, whatsapp_no: 1, mobile_no: 1, mobile_no_3: 1, mobile_no_4: 1 } }).toArray()) {
        for (const f of ['whatsapp_no', 'mobile_no', 'mobile_no_3', 'mobile_no_4']) {
            const n = V.normalizePhone(c[f]); if (n) { phones.set(n, c.customer_name || String(c._id)); nameOfPhone.set(n, c.customer_name || ''); }
        }
    }
    for (const p of await profs.find({}, { projection: { contacts: 1, customerCode: 1 } }).toArray()) {
        (p.contacts || []).forEach((k) => k.number && phones.set(k.number, p.customerCode));
    }
    const byCode = new Map((await profs.find({}, { projection: { customerId: 1, customerCode: 1 } }).toArray()).map((p) => [p.customerCode, p.customerId]));
    let sl = ((await custs.find({}, { projection: { sl_no: 1 } }).sort({ sl_no: -1 }).limit(1).toArray())[0] || {}).sl_no || 0;

    const report = { mode: APPLY ? 'APPLY' : 'DRY-RUN', source: SOURCE_DB, total: 0, inserted: 0, wouldInsert: 0,
        skippedExisting: [], skippedDuplicatePhone: [], issues: [], samples: [] };

    let cursor = sdb.collection('customers').find({}).sort({ Account_Creation: 1 });
    if (LIMIT) cursor = cursor.limit(LIMIT);

    for await (const s of cursor) {
        report.total++;
        const code = String(s.Customer_ID || '').toUpperCase();
        const name = decode(s.Name);
        const tag = `${code || s._id} (${name || 'no name'})`;

        if (!name || name.length < 2) { report.issues.push({ customer: tag, problem: 'missing name — skipped' }); continue; }
        if (code && codes.has(code)) { report.skippedExisting.push(tag); continue; }

        // phones: keep every number; invalid ones are reported and preserved in notes
        const rawNums = [s.Mobile_No1, s.Mobile_No2].map((x) => (x == null ? '' : String(x))).filter((x) => x.trim());
        const contacts = []; const badNums = [];
        rawNums.forEach((raw, i) => {
            const n = V.normalizePhone(raw);
            if (V.isPhone10(n) && !contacts.some((c) => c.number === n)) contacts.push({ number: n, label: i === 0 ? 'whatsapp' : 'mobile' });
            else if (!V.isPhone10(n)) badNums.push(raw);
        });
        if (badNums.length) report.issues.push({ customer: tag, problem: `invalid phone(s): ${badNums.join(', ')} (kept in notes)` });
        if (!contacts.length) { report.issues.push({ customer: tag, problem: 'no valid phone number — skipped' }); continue; }
        const dupe = contacts.find((c) => phones.has(c.number));
        if (dupe) { report.skippedDuplicatePhone.push({ customer: tag, number: dupe.number, existing: phones.get(dupe.number) }); continue; }

        const membership = ['Regular', 'VIP'].includes(s.Membership_Status) ? s.Membership_Status : 'Regular';
        if (s.Membership_Status && membership !== s.Membership_Status) report.issues.push({ customer: tag, problem: `unknown membership "${s.Membership_Status}" -> Regular` });
        const gender = ['Male', 'Female', 'Other'].includes(s.Gender) ? s.Gender : '';
        const dob = s.dob && !Number.isNaN(new Date(s.dob).getTime()) ? new Date(s.dob) : undefined;
        const created = s.Account_Creation instanceof Date ? s.Account_Creation : new Date();

        // Referred_By is free text: link it when it is a known code or a unique mobile.
        let referredBy;
        const refText = decode(s.Referred_By);
        if (refText) {
            const refCode = refText.toUpperCase();
            const refPhone = V.normalizePhone(refText);
            if (byCode.has(refCode)) referredBy = { customerId: byCode.get(refCode), code: refCode, text: refText };
            else if (V.isPhone10(refPhone) && phones.has(refPhone)) referredBy = { mobile: refPhone, name: nameOfPhone.get(refPhone) || phones.get(refPhone), text: refText };
            else referredBy = { text: refText };
        }

        const notes = [decode(s.Notes), badNums.length ? `Original phone(s) needing review: ${badNums.join(', ')}` : ''].filter(Boolean).join('\n');
        const customerId = new ObjectId();
        sl += 1;
        const legacyDoc = {
            _id: customerId,
            customer_name: name, customer_name_bengali: decode(s.Name_Bn) || '',
            address: decode(s.Address) || '', address_bengali: '',
            whatsapp_no: contacts[0].number, mobile_no: contacts[1] ? contacts[1].number : '',
            ...(s.Email ? { email: decode(s.Email) } : {}),
            ...(s.Nickname ? { nickname: decode(s.Nickname) } : {}),
            notification_type: 'all', created_by: 'migration', created_by_name: 'LGPAdmin migration',
            created_at: created, updated_at: new Date(), sl_no: sl,
        };
        const profileDoc = {
            customerId, customerCode: code || `LGP${ymd(created)}${crypto.randomBytes(2).toString('hex').toUpperCase().slice(0, 3)}`,
            branchId: BRANCH, branchName: BRANCH === 'main' ? 'Main branch' : BRANCH,
            membershipStatus: membership, nicknameBn: decode(s.Nickname_Bn) || undefined,
            addressBn: decode(s.Address_Bn) || undefined, gender, dob, contacts, referredBy,
            notes: notes || undefined, profilePicUrl: s.profilePic || undefined,
            country: 'India', source: 'lgpadmin', sourceId: String(s.Customer_ID || s._id),
            createdBy: 'migration', createdByName: 'LGPAdmin migration', createdAt: created, updatedAt: new Date(),
        };
        const fin = await sdb.collection('customer_finance').findOne({ Customer_ID: s.Customer_ID });
        const finDoc = fin ? {
            customerId, customerCode: profileDoc.customerCode, totalDue: fin.Total_Due || 0, lgpWallet: fin.LGP_Wallet || 0,
            totalPurchases: fin.Total_Purchases || 0, lastPaymentDate: fin.Last_Payment_Date || null,
            source: 'lgpadmin', createdAt: new Date(),
        } : null;

        if (report.samples.length < 3) report.samples.push({ legacyDoc, profileDoc, finDoc });
        contacts.forEach((c) => { phones.set(c.number, profileDoc.customerCode); nameOfPhone.set(c.number, name); });
        codes.add(profileDoc.customerCode); byCode.set(profileDoc.customerCode, customerId);

        if (APPLY) {
            await custs.insertOne(legacyDoc);
            await profs.insertOne(profileDoc);
            if (finDoc) await fins.insertOne(finDoc);
            report.inserted++;
        } else {
            report.wouldInsert++;
        }
    }

    console.log(`\n${report.mode}  —  source ${SOURCE_DB}`);
    console.log(`  customers read:            ${report.total}`);
    console.log(`  ${APPLY ? 'inserted' : 'would insert'}:${' '.repeat(APPLY ? 17 : 12)}${APPLY ? report.inserted : report.wouldInsert}`);
    console.log(`  skipped (already there):   ${report.skippedExisting.length}`);
    console.log(`  skipped (duplicate phone): ${report.skippedDuplicatePhone.length}`);
    console.log(`  issues to review:          ${report.issues.length}`);
    report.issues.slice(0, 15).forEach((i) => console.log(`    - ${i.customer}: ${i.problem}`));
    if (REPORT) { fs.writeFileSync(REPORT, JSON.stringify(report, null, 2)); console.log(`  full report: ${REPORT}`); }
    if (!APPLY) console.log('\nDry run only — nothing was written. Re-run with --apply to insert.');

    await Promise.all([src.close(), tgt.close()]);
})().catch((e) => { console.error('migration failed:', e); process.exit(1); });
