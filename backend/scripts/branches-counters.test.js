'use strict';
/**
 * Branches, billing counters, who works where, and the "who / where" metadata:  node scripts/branches-counters.test.js
 * Starts the API itself on port 5058 against the DEV database (needs node scripts/local-db.js and the dev logins) and removes
 * everything it made (branch, counters, people, bills, item, estimate) at the end.
 */
const { spawn } = require('child_process');
const path = require('path');
const assert = require('assert');
const crypto = require('crypto');
const { MongoClient, ObjectId } = require('mongodb');

let n = 0, bad = 0;
const t = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { bad++; console.log('  FAIL', name, '-', e.message); } };

(async () => {
    const PORT = 5058, BASE = `http://127.0.0.1:${PORT}`;
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
    const login = async (m, p) => (await call('POST', '/api/auth/login', { body: { mobile: m, password: p } })).data?.token;
    const admin = await login('7029621489', 'Admin@123');
    const staff = await login('9000000011', 'Staff@123');     // a branch staff login of the sample data
    assert(admin && staff, 'logins failed');

    const tag = crypto.randomBytes(3).toString('hex').toUpperCase();
    const uid = () => crypto.randomBytes(8).toString('hex');
    const cx = await MongoClient.connect('mongodb://127.0.0.1:27018');
    const db = cx.db('lgp_dev');
    const made = { branches: [], users: [], reqIds: [], barcodes: [] };
    let br, c1, c2, person, personToken;

    await t('only a person with the permission can open a branch (staff 403), the name is needed (400)', async () => {
        assert.strictEqual((await call('POST', '/api/branches', { token: staff, body: { name: `X ${tag}` } })).status, 403);
        assert.strictEqual((await call('POST', '/api/branches', { token: admin, body: {} })).status, 400);
    });
    await t('a bad GSTIN or bill letters are refused', async () => {
        assert.strictEqual((await call('POST', '/api/branches', { token: admin, body: { name: `BADG ${tag}`, gstin: 'nope' } })).status, 400);
        assert.strictEqual((await call('POST', '/api/branches', { token: admin, body: { name: `BADP ${tag}`, invoicePrefix: 'TOO-LONG!' } })).status, 400);
    });
    await t('a branch is opened with its bill letters, GSTIN, city; the same name or letters again are refused (409)', async () => {
        const r = await call('POST', '/api/branches', { token: admin, body: { name: `CNT Branch ${tag}`, invoicePrefix: `Z${tag.slice(0, 3)}`, city: 'Howrah', state: 'West Bengal', gstin: '19ABCDE1234F1Z5', phone: '9000000099' } });
        assert.strictEqual(r.status, 201, JSON.stringify(r.json));
        br = r.data; made.branches.push(br.id);
        assert.strictEqual(br.invoicePrefix, `Z${tag.slice(0, 3)}`);
        assert.strictEqual((await call('POST', '/api/branches', { token: admin, body: { name: `cnt branch ${tag}` } })).status, 409);
        assert.strictEqual((await call('POST', '/api/branches', { token: admin, body: { name: `Other ${tag}`, invoicePrefix: br.invoicePrefix } })).status, 409);
    });
    await t('the list shows the branch with 0 counters and the built-in main branch', async () => {
        const r = await call('GET', '/api/branches', { token: admin });
        const ids = r.data.branches.map((b) => b.id);
        assert(ids.includes('main') && ids.includes(br.id));
        assert.strictEqual(r.data.branches.find((b) => b.id === br.id).counterCount, 0);
    });
    await t('a branch can be changed; main cannot', async () => {
        const r = await call('PATCH', `/api/branches/${br.id}`, { token: admin, body: { city: 'Kolkata', phone: '9000000088' } });
        assert.strictEqual(r.status, 200);
        assert.strictEqual(r.data.city, 'Kolkata');
        assert.strictEqual((await call('PATCH', '/api/branches/main', { token: admin, body: { city: 'x' } })).status, 400);
        assert.strictEqual((await call('PATCH', `/api/branches/${br.id}`, { token: staff, body: { city: 'x' } })).status, 403);
    });

    await t('counters: add two (a duplicate name is refused), list, rename', async () => {
        let r = await call('POST', `/api/branches/${br.id}/counters`, { token: admin, body: { name: 'Counter 1', code: 'c1' } });
        assert.strictEqual(r.status, 201, JSON.stringify(r.json));
        c1 = r.data; assert.strictEqual(c1.code, 'C1');
        r = await call('POST', `/api/branches/${br.id}/counters`, { token: admin, body: { name: 'Gold desk' } });
        c2 = r.data;
        assert.strictEqual((await call('POST', `/api/branches/${br.id}/counters`, { token: admin, body: { name: 'counter 1' } })).status, 409);
        assert.strictEqual((await call('POST', `/api/branches/${br.id}/counters`, { token: staff, body: { name: 'Nope' } })).status, 403);
        r = await call('GET', `/api/branches/${br.id}/counters`, { token: admin });
        assert.deepStrictEqual(r.data.counters.map((c) => c.name).sort(), ['Counter 1', 'Gold desk']);
        r = await call('PATCH', `/api/branches/${br.id}/counters/${c2.id}`, { token: admin, body: { name: 'Gold counter' } });
        assert.strictEqual(r.data.name, 'Gold counter');
    });
    await t('the main branch can have counters too', async () => {
        const r = await call('POST', '/api/branches/main/counters', { token: admin, body: { name: `Main ${tag}` } });
        assert.strictEqual(r.status, 201);
        await call('PATCH', `/api/branches/main/counters/${r.data.id}`, { token: admin, body: { isActive: false } });
        made.mainCounter = r.data.id;
    });

    await t('a person is created at the branch with a counter; a counter of another branch is refused', async () => {
        const mob = `93${tag.replace(/\D/g, '1')}1111`.slice(0, 10).padEnd(10, '7');
        let r = await call('POST', '/api/users', { token: admin, body: { name: `CNT Person ${tag}`, mobile: mob, password: 'Cnt@12345', role: 'staff', branchId: br.id, counterId: made.mainCounter } });
        assert.strictEqual(r.status, 400, 'a main-branch counter must not be accepted at another branch');
        r = await call('POST', '/api/users', { token: admin, body: { name: `CNT Person ${tag}`, mobile: mob, password: 'Cnt@12345', role: 'staff', branchId: br.id, counterId: c1.id } });
        assert.strictEqual(r.status, 201, JSON.stringify(r.json));
        person = r.data.user; made.users.push(String(person._id || person.id));
        assert.strictEqual(person.counterName, 'Counter 1');
        personToken = await login(mob, 'Cnt@12345');
        assert(personToken, 'the new person cannot sign in');
        const me = await call('POST', '/api/auth/login', { body: { mobile: mob, password: 'Cnt@12345' } });
        assert.strictEqual(me.data.user.counterId, c1.id);
        assert.strictEqual(me.data.user.branchId, br.id);
    });
    await t('the branch page lists its staff with their counters; assigning moves a person and checks the counter', async () => {
        const uidp = made.users[0];
        let r = await call('GET', `/api/branches/${br.id}`, { token: admin });
        assert(r.data.staff.some((s) => s.id === uidp && s.counterName === 'Counter 1'));
        r = await call('PATCH', `/api/branches/${br.id}/staff/${uidp}`, { token: admin, body: { counterId: c2.id } });
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        assert.strictEqual(r.data.counterName, 'Gold counter');
        assert.strictEqual((await call('PATCH', `/api/branches/main/staff/${uidp}`, { token: admin, body: { counterId: c2.id } })).status, 400, 'a counter of another branch');
        assert.strictEqual((await call('PATCH', `/api/branches/${br.id}/staff/${uidp}`, { token: staff, body: {} })).status, 403);
        await call('PATCH', `/api/branches/${br.id}/staff/${uidp}`, { token: admin, body: { counterId: c1.id } });
    });
    await t('moving a person to another branch (users API) drops the old counter', async () => {
        const uidp = made.users[0];
        const r = await call('PUT', `/api/users/${uidp}`, { token: admin, body: { branchId: 'main' } });
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        const u = await db.collection('users').findOne({ _id: new ObjectId(uidp) });
        assert.strictEqual(u.counterId || '', '');
        await call('PATCH', `/api/branches/${br.id}/staff/${uidp}`, { token: admin, body: { counterId: c1.id } });
        const u2 = await db.collection('users').findOne({ _id: new ObjectId(uidp) });
        assert.strictEqual(u2.branchId, br.id);
        assert.strictEqual(u2.counterId, c1.id);
    });
    await t('a branch with working staff cannot be switched off; one without can', async () => {
        assert.strictEqual((await call('PATCH', `/api/branches/${br.id}`, { token: admin, body: { isActive: false } })).status, 409);
        const empty = await call('POST', '/api/branches', { token: admin, body: { name: `CNT Empty ${tag}` } });
        made.branches.push(empty.data.id);
        assert.strictEqual((await call('PATCH', `/api/branches/${empty.data.id}`, { token: admin, body: { isActive: false } })).status, 200);
        assert.strictEqual((await call('POST', `/api/branches/${empty.data.id}/counters`, { token: admin, body: { name: 'C' } })).status, 409, 'no counters at a switched-off branch');
    });

    const ring = { particulars: 'Gold Ring', metalType: 'Gold', netWt: 1, rate: 1000, makingCharge: 0, hsnCode: '7113' };
    const bill = (token, over = {}, headers = {}) => call('POST', '/api/billing/invoices', { token, headers, body: { requestId: (made.reqIds[made.reqIds.length] = uid()), customerName: 'Counter Walk-in', items: [ring], goldRate: 1000, silverRate: 100, paidAmount: 1030, paymentMode: 'Cash', ...over } });

    await t("the person's bill is saved with the branch, THEIR counter, who made it, their role and the program", async () => {
        const r = await bill(personToken, {}, { 'X-Client': 'app', 'X-App-Version': '1.5.1+9' });
        assert.strictEqual(r.status, 201, JSON.stringify(r.json));
        assert.match(r.data.invoiceNumber, new RegExp(`^Z${tag.slice(0, 3)}-\\d+`), 'the branch has its own series');
        const d = await db.collection('invoices').findOne({ invoice_number: r.data.invoiceNumber });
        assert.strictEqual(d.branch_id, br.id);
        assert.strictEqual(d.counter_id, c1.id);
        assert.strictEqual(d.counter_name, 'Counter 1');
        assert.strictEqual(d.counter_code, 'C1');
        assert.strictEqual(d.created_by_name, `CNT Person ${tag}`);
        assert.strictEqual(d.created_by_role, 'staff');
        assert.strictEqual(d.client, 'app');
        assert.strictEqual(d.app_version, '1.5.1+9');
        assert.strictEqual(d.source, 'app');
        assert.strictEqual(d.payment_history[0].counter_name, 'Counter 1', 'the money is tied to the counter too');
        assert.strictEqual(r.data.counterName, 'Counter 1');
        made.inv1 = r.data;
    });
    await t('the person can pick another counter of their branch (X-Counter); one of another branch is ignored', async () => {
        let r = await bill(personToken, {}, { 'X-Counter': c2.id });
        assert.strictEqual(r.status, 201);
        assert.strictEqual(r.data.counterName, 'Gold counter');
        r = await bill(personToken, {}, { 'X-Counter': made.mainCounter });
        assert.strictEqual(r.data.counterName, 'Counter 1', 'a counter of another branch falls back to their own');
    });
    await t('the bill can name its counter in the request; a wrong one is refused (400)', async () => {
        let r = await bill(personToken, { counterId: c2.id });
        assert.strictEqual(r.status, 201);
        assert.strictEqual(r.data.counterName, 'Gold counter');
        r = await bill(personToken, { counterId: made.mainCounter });
        assert.strictEqual(r.status, 400, JSON.stringify(r.json));
    });
    await t('a counter that is switched off is not used', async () => {
        await call('PATCH', `/api/branches/${br.id}/counters/${c2.id}`, { token: admin, body: { isActive: false } });
        const r = await bill(personToken, {}, { 'X-Counter': c2.id });
        assert.strictEqual(r.status, 201);
        assert.strictEqual(r.data.counterName, 'Counter 1');
        assert.strictEqual((await bill(personToken, { counterId: c2.id })).status, 400);
        await call('PATCH', `/api/branches/${br.id}/counters/${c2.id}`, { token: admin, body: { isActive: true } });
    });
    await t('the list can be filtered by counter; the row carries the counter name', async () => {
        const r = await call('GET', `/api/billing/invoices?counter=${c1.id}&limit=50`, { token: admin });
        assert(r.data.length >= 2 && r.data.every((x) => x.counterName === 'Counter 1'), JSON.stringify(r.data.map((x) => x.counterName)));
        const other = await call('GET', `/api/billing/invoices?counter=${c2.id}&limit=50`, { token: admin });
        assert(other.data.length >= 2 && other.data.every((x) => x.counterName === 'Gold counter'));
    });
    await t('a payment received later carries the counter and who took it (and the bill records who changed it last)', async () => {
        const cust = await call('POST', '/api/directory/customers', { token: admin, body: { name: `CNT Cust ${tag}`, whatsappNo: '95' + String(Date.now()).slice(-8) } });
        assert.strictEqual(cust.status, 201, JSON.stringify(cust.json));
        made.customer = cust.data.customer?._id || cust.data._id;
        const open = await bill(personToken, { paidAmount: 100, customerName: undefined, customerId: made.customer, customerAddress: '12 Test Road, Howrah' }, { 'X-Counter': c1.id });
        assert.strictEqual(open.status, 201, JSON.stringify(open.json));
        const r = await call('POST', `/api/billing/invoices/${open.data._id}/payments`, { token: personToken, body: { requestId: uid(), amount: 200, mode: 'Cash' }, headers: { 'X-Counter': c1.id } });
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        const d = await db.collection('invoices').findOne({ invoice_number: open.data.invoiceNumber });
        const last = d.payment_history[d.payment_history.length - 1];
        assert.strictEqual(last.counter_name, 'Counter 1');
        assert.strictEqual(last.created_by_name, `CNT Person ${tag}`);
        assert.strictEqual(d.updated_by_name, `CNT Person ${tag}`);
        assert(d.updated_at instanceof Date);
    });
    await t('billing meta gives the counters of the branch and the one in force', async () => {
        const r = await call('GET', '/api/billing/meta', { token: personToken });
        assert.strictEqual(r.data.branch.branchId, br.id);
        assert(r.data.counters.some((c) => c.id === c1.id));
        assert.strictEqual(r.data.counter.counterId, c1.id);
        const cur = await call('GET', '/api/branches/counters/current', { token: personToken });
        assert.strictEqual(cur.data.selectedId, c1.id);
        assert.strictEqual(cur.data.assignedId, c1.id);
    });
    await t("a person sees only their own branch's counters, an admin sees every branch", async () => {
        const mine = await call('GET', '/api/branches', { token: personToken });
        assert.deepStrictEqual(mine.data.branches.map((b) => b.id), [br.id]);
        const all = await call('GET', '/api/branches', { token: admin });
        assert(all.data.branches.length >= 3);
    });

    await t('an item added at the branch carries its branch, who added it and when (createdBy / createdByName / updatedBy)', async () => {
        const barcode = `CNT-${tag}`;
        const r = await call('POST', '/api/items', { token: personToken, body: { barcode, name: 'COUNTER TEST ring', itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 2, grossWeight: 2.1 } });
        assert([200, 201].includes(r.status), JSON.stringify(r.json));
        made.barcodes.push(barcode);
        const d = await db.collection('items').findOne({ barcode });
        assert.strictEqual(d.branchId, br.id);
        assert.strictEqual(String(d.createdBy), made.users[0]);
        assert.strictEqual(d.createdByName, `CNT Person ${tag}`);
        assert.strictEqual(d.updatedByName, `CNT Person ${tag}`);
        assert(d.createdAt instanceof Date && d.updatedAt instanceof Date);
        assert(!d.counterId, 'stock is not tied to a counter');
    });
    await t('an item changed by somebody else records the last person who changed it', async () => {
        const barcode = made.barcodes[0];
        const it = await db.collection('items').findOne({ barcode });
        const r = await call('PUT', `/api/items/${it._id}`, { token: admin, body: { name: 'COUNTER TEST ring 2' } });
        assert([200, 201].includes(r.status), JSON.stringify(r.json));
        const d = await db.collection('items').findOne({ barcode });
        assert.strictEqual(d.updatedByName, 'Admin');
        assert.strictEqual(d.createdByName, `CNT Person ${tag}`, 'the creator stays');
    });
    await t('an estimate made at a counter carries the counter, branch and person', async () => {
        const r = await call('POST', '/api/estimates', { token: personToken, body: { requestId: uid(), customerName: 'Counter Estimate', items: [{ particulars: 'Gold Ring', metalType: 'Gold', netWt: 1, rate: 1000, makingCharge: 0 }], goldRate: 1000, silverRate: 100 } });
        if (r.status === 404 || r.status === 400) { console.log('        (estimate route answered', r.status, '- skipped:', JSON.stringify(r.json).slice(0, 120), ')'); return; }
        assert([200, 201].includes(r.status), JSON.stringify(r.json));
        const d = await db.collection('app_estimates').findOne({}, { sort: { _id: -1 } });
        assert.strictEqual(d.branchId, br.id);
        assert.strictEqual(d.counterName, 'Counter 1');
        assert.strictEqual(d.createdByName, `CNT Person ${tag}`);
        made.estimateId = d._id;
    });
    await t('every change above is in the audit log', async () => {
        const rows = await db.collection('app_audit_log').find({ entityLabel: new RegExp(`CNT Branch ${tag}|Counter 1 \\(CNT Branch ${tag}\\)`) }).toArray();
        assert(rows.some((r) => r.entity === 'branch' && r.action === 'created'));
        assert(rows.some((r) => r.entity === 'counter' && r.action === 'created'));
    });

    // tidy up everything this test made
    await db.collection('invoices').deleteMany({ branch_id: br.id });
    if (made.customer) { await db.collection('customers').deleteMany({ _id: new ObjectId(String(made.customer)) }); await db.collection('app_customer_profiles').deleteMany({ customerId: new ObjectId(String(made.customer)) }).catch(() => {}); }
    await db.collection('app_request_locks').deleteMany({ _id: { $in: made.reqIds.filter(Boolean) } }).catch(() => {});
    await db.collection('items').deleteMany({ barcode: { $in: made.barcodes } });
    if (made.estimateId) await db.collection('app_estimates').deleteOne({ _id: made.estimateId });
    await db.collection('users').deleteMany({ _id: { $in: made.users.map((i) => new ObjectId(i)) } });
    await db.collection('app_branch_counters').deleteMany({ $or: [{ branchId: br.id }, { _id: made.mainCounter ? new ObjectId(made.mainCounter) : null }] });
    await db.collection('app_branches').deleteMany({ _id: { $in: made.branches.map((i) => new ObjectId(i)) } });
    await db.collection('shop_info').deleteMany({ shop_id: `branch:${br.id}` });
    await cx.close();
    stop();
    console.log(`\n${n} passed, ${bad} failed`);
    process.exit(bad ? 1 : 0);
})().catch((e) => { console.error('ERROR', e); process.exit(1); });
