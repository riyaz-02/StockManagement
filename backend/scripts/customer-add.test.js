'use strict';
/**
 * Adding a customer the way the website does it:  node scripts/customer-add.test.js
 * Several phone numbers, "already saved" on ANY of them, the Bengali name / address (also made by the server when none is sent),
 * the four message choices, and the serial number. Starts the API itself on port 5059 (DEV database), removes what it makes.
 */
const { spawn } = require('child_process');
const path = require('path');
const assert = require('assert');
const crypto = require('crypto');
const { MongoClient, ObjectId } = require('mongodb');

let n = 0, bad = 0;
const t = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { bad++; console.log('  FAIL', name, '-', e.message); } };

(async () => {
    const PORT = 5059, BASE = `http://127.0.0.1:${PORT}`;
    const srv = spawn(process.execPath, ['server.js'], { cwd: path.join(__dirname, '..'), env: { ...process.env, PORT: String(PORT), AUTH_LIMIT_MAX: '2000', RATE_LIMIT_MAX_REQUESTS: '20000' }, stdio: 'ignore' });
    const stop = () => { try { srv.kill(); } catch (_) { /* gone */ } };
    process.on('exit', stop);
    for (let i = 0; i < 90; i++) { try { const r = await fetch(BASE + '/api/app-version'); if (r.ok) break; } catch (_) { /* not up yet */ } await new Promise((r) => setTimeout(r, 1000)); }
    const call = async (method, url, { token, body, headers = {} } = {}) => {
        const h = { ...headers };
        if (token) h.Authorization = `Bearer ${token}`;
        if (body !== undefined) h['Content-Type'] = 'application/json';
        const r = await fetch(BASE + url, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body) });
        const json = await r.json().catch(() => ({}));
        return { status: r.status, json, data: json.data };
    };
    const admin = (await call('POST', '/api/auth/login', { body: { mobile: '7029621489', password: 'Admin@123' } })).data?.token;
    assert(admin, 'login failed');

    const tag = crypto.randomBytes(3).toString('hex').toUpperCase();
    const base = 9000000000 + Math.floor(Math.random() * 90000000);          // 9 000 000 000 .. 9 089 999 999
    const num = (k) => String(base + k * 7);
    const cx = await MongoClient.connect('mongodb://127.0.0.1:27018');
    const db = cx.db('lgp_dev');
    const made = [];
    let first;

    await t('a customer with three numbers, the Bengali address and "offers only" is saved in the website shape', async () => {
        const r = await call('POST', '/api/directory/customers', { token: admin, body: {
            name: `CAT Rina ${tag}`, nameBengali: 'রিনা', address: '12 Test Lane', addressBengali: '১২ টেস্ট লেন', notificationType: 'offers',
            contacts: [{ number: num(1), label: 'whatsapp' }, { number: num(2), label: 'mobile' }, { number: num(3), label: 'home' }],
        } });
        assert.strictEqual(r.status, 201, JSON.stringify(r.json));
        first = r.data; made.push(first._id);
        const d = await db.collection('customers').findOne({ _id: new ObjectId(first._id) });
        assert.strictEqual(d.whatsapp_no, num(1));
        assert.strictEqual(d.mobile_no, num(2));
        assert.strictEqual(d.mobile_no_3, num(3), 'the third number goes to the website\'s third slot');
        assert.strictEqual(d.customer_name_bengali, 'রিনা');
        assert.strictEqual(d.address_bengali, '১২ টেস্ট লেন', 'the website reads address_bengali');
        assert.strictEqual(d.notification_type, 'offers');
        assert(d.sl_no > 0, 'a serial number');
        assert(d.created_by_name && d.created_at, 'who and when');
    });
    await t('any of its numbers is "already saved": the 1st, the 2nd and the 3rd (409), a second customer needs force', async () => {
        for (const k of [1, 2, 3]) {
            const r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CAT Other ${tag}`, contacts: [{ number: num(10 + k), label: 'whatsapp' }, { number: num(k), label: 'mobile' }] } });
            assert.strictEqual(r.status, 409, `number ${k}: ${JSON.stringify(r.json)}`);
            assert.match(r.json.message, /already exists/);
        }
        const forced = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CAT Twin ${tag}`, force: true, contacts: [{ number: num(1), label: 'whatsapp' }] } });
        assert.strictEqual(forced.status, 201, JSON.stringify(forced.json));
        made.push(forced.data._id);
    });
    await t('the live check finds the customer by any number, marks an exact match and gives the serial number', async () => {
        const r = await call('GET', `/api/directory/customers/lookup?q=${num(3)}`, { token: admin });
        const hit = r.data.find((x) => x.id === first._id);
        assert(hit && hit.exact === true && hit.matchedNumber === num(3));
        assert(hit.serialNo > 0 && hit.phones.length === 3);
        const part = await call('GET', `/api/directory/customers/lookup?q=${num(2).slice(0, 7)}`, { token: admin });
        assert(part.data.find((x) => x.id === first._id && x.exact === false), 'a part of a number is a similar match, not an exact one');
        const own = await call('GET', `/api/directory/customers/lookup?q=${num(3)}&exclude=${first._id}`, { token: admin });
        assert(!own.data.find((x) => x.id === first._id), 'the customer being edited is not offered');
    });
    await t('bad numbers are refused with the reason: 9 digits, the same number twice, more than 6', async () => {
        let r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CAT Bad ${tag}`, contacts: [{ number: '98300', label: 'whatsapp' }] } });
        assert.strictEqual(r.status, 400); assert.match(r.json.message, /10-digit/);
        r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CAT Bad ${tag}`, contacts: [{ number: num(20), label: 'whatsapp' }, { number: num(20), label: 'mobile' }] } });
        assert.strictEqual(r.status, 400); assert.match(r.json.message, /more than once/);
        r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CAT Bad ${tag}`, contacts: [1, 2, 3, 4, 5, 6, 7].map((k) => ({ number: num(30 + k), label: 'mobile' })) } });
        assert.strictEqual(r.status, 400); assert.match(r.json.message, /at most 6/);
        r = await call('POST', '/api/directory/customers', { token: admin, body: { name: 'x', contacts: [{ number: num(21), label: 'whatsapp' }] } });
        assert.strictEqual(r.status, 400);
    });
    await t('all four message choices are kept; anything else becomes "all"', async () => {
        for (const [i, choice] of [['all', 'all'], ['invitations', 'invitations'], ['none', 'none'], ['nonsense', 'all']].entries()) {
            const r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CAT Notify ${choice[0]} ${tag}`, notificationType: choice[0], contacts: [{ number: num(40 + i), label: 'whatsapp' }] } });
            assert.strictEqual(r.status, 201, JSON.stringify(r.json));
            made.push(r.data._id);
            const d = await db.collection('customers').findOne({ _id: new ObjectId(r.data._id) });
            assert.strictEqual(d.notification_type, choice[1]);
        }
    });
    await t('without a Bengali name or address the server makes them (when the translation service answers)', async () => {
        const r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `Rahul Das`, address: 'Bagbazar, Kolkata', contacts: [{ number: num(50), label: 'whatsapp' }] } });
        assert.strictEqual(r.status, 201, JSON.stringify(r.json));
        made.push(r.data._id);
        const d = await db.collection('customers').findOne({ _id: new ObjectId(r.data._id) });
        if (!d.customer_name_bengali) { console.log('        (the Bengali service did not answer: skipped)'); return; }
        assert(/[ঀ-৿]/.test(d.customer_name_bengali), 'Bengali letters');
        assert(/[ঀ-৿]/.test(d.address_bengali), 'Bengali address');
    });
    await t('what the person typed in Bengali is never replaced by the server', async () => {
        const r = await call('POST', '/api/directory/customers', { token: admin, body: { name: 'Sumit Roy', nameBengali: 'সুমিত (হাতে লেখা)', address: 'Howrah', contacts: [{ number: num(51), label: 'whatsapp' }] } });
        made.push(r.data._id);
        const d = await db.collection('customers').findOne({ _id: new ObjectId(r.data._id) });
        assert.strictEqual(d.customer_name_bengali, 'সুমিত (হাতে লেখা)');
    });
    await t('a partial edit keeps the numbers and saves the Bengali address and the message choice', async () => {
        const r = await call('PUT', `/api/directory/customers/${first._id}/partial`, { token: admin, body: { addressBengali: 'নতুন ঠিকানা', notificationType: 'invitations' } });
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        const d = await db.collection('customers').findOne({ _id: new ObjectId(first._id) });
        assert.strictEqual(d.address_bengali, 'নতুন ঠিকানা');
        assert.strictEqual(d.notification_type, 'invitations');
        assert.strictEqual(d.mobile_no_3, num(3), 'the third number is still there');
        assert.strictEqual(d.whatsapp_no, num(1));
    });
    await t('editing a number to one that another customer has is refused', async () => {
        const other = made.find((id) => id !== first._id);
        const r = await call('PUT', `/api/directory/customers/${other}/partial`, { token: admin, body: { contacts: [{ number: num(2), label: 'whatsapp' }] } });
        assert.strictEqual(r.status, 409, JSON.stringify(r.json));
        assert.match(r.json.message, /already uses/);
    });
    await t('important dates: several occasions are saved in the website\'s `anniversaries`, the profile follows, bad ones are refused', async () => {
        let r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CAT Dates ${tag}`, contacts: [{ number: num(60), label: 'whatsapp' }],
            importantDates: [{ occasion: 'Birthday', date: '1990-05-17' }, { occasion: 'Marriage Anniversary', date: '2015-02-14' }, { occasion: "Son's Birthday", date: '2018-11-03' }, { occasion: '', date: '' }] } });
        assert.strictEqual(r.status, 201, JSON.stringify(r.json));
        made.push(r.data._id);
        const d = await db.collection('customers').findOne({ _id: new ObjectId(r.data._id) });
        assert.deepStrictEqual(d.anniversaries.map((a) => a.occasion), ['Birthday', 'Marriage Anniversary', "Son's Birthday"], 'the empty row is dropped');
        assert.strictEqual(new Date(d.anniversaries[0].date).toISOString().slice(0, 10), '1990-05-17');
        const p = await db.collection('app_customer_profiles').findOne({ customerId: new ObjectId(r.data._id) });
        assert.strictEqual(new Date(p.dob).toISOString().slice(0, 10), '1990-05-17', 'profile birth date follows the list');
        assert.strictEqual(new Date(p.anniversary).toISOString().slice(0, 10), '2015-02-14', 'profile anniversary follows the list');
        r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CAT Dates2 ${tag}`, contacts: [{ number: num(61), label: 'whatsapp' }], importantDates: [{ occasion: 'Birthday', date: '' }] } });
        assert.strictEqual(r.status, 400); assert.match(r.json.message, /both an occasion and a date/);
        r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CAT Dates2 ${tag}`, contacts: [{ number: num(61), label: 'whatsapp' }], importantDates: [{ occasion: 'Birthday', date: '2020-13-45' }] } });
        assert.strictEqual(r.status, 400); assert.match(r.json.message, /not a valid date/);
    });
    await t('important dates: an older client sending dob / anniversary still gets a list; a partial edit keeps it; sending [] clears it', async () => {
        let r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CAT Old ${tag}`, contacts: [{ number: num(62), label: 'whatsapp' }], dob: '1985-01-02', anniversary: '2010-03-04' } });
        assert.strictEqual(r.status, 201, JSON.stringify(r.json));
        const id = r.data._id; made.push(id);
        let d = await db.collection('customers').findOne({ _id: new ObjectId(id) });
        assert.deepStrictEqual(d.anniversaries.map((a) => a.occasion), ['Birthday', 'Marriage Anniversary']);
        r = await call('PUT', `/api/directory/customers/${id}/partial`, { token: admin, body: { importantDates: [...d.anniversaries.map((a) => ({ occasion: a.occasion, date: new Date(a.date).toISOString().slice(0, 10) })), { occasion: 'Engagement', date: '2009-12-25' }] } });
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        r = await call('PUT', `/api/directory/customers/${id}/partial`, { token: admin, body: { notificationType: 'none' } });
        d = await db.collection('customers').findOne({ _id: new ObjectId(id) });
        assert.strictEqual(d.anniversaries.length, 3, 'an edit of something else keeps the dates');
        r = await call('PUT', `/api/directory/customers/${id}/partial`, { token: admin, body: { importantDates: [] } });
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        d = await db.collection('customers').findOne({ _id: new ObjectId(id) });
        assert.strictEqual((d.anniversaries || []).length, 0);
        const p = await db.collection('app_customer_profiles').findOne({ customerId: new ObjectId(id) });
        assert(!p.dob && !p.anniversary, 'the profile dates are cleared with the list');
    });

    for (const id of made) {
        await db.collection('customers').deleteOne({ _id: new ObjectId(id) });
        await db.collection('app_customer_profiles').deleteMany({ customerId: new ObjectId(id) });
    }
    await cx.close();
    stop();
    console.log(`\n${n} passed, ${bad} failed`);
    process.exit(bad ? 1 : 0);
})().catch((e) => { console.error('ERROR', e); process.exit(1); });
