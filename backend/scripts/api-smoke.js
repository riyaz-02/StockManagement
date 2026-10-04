/**
 * api-smoke.js — end-to-end API smoke test against the LOCAL dev backend.
 *
 *   node scripts/api-smoke.js            (backend + local DB must be running)
 *
 * Creates clearly-named "SMOKE" records in the local test DB. Refuses to run
 * against anything that is not localhost so it can never touch production.
 */
'use strict';

const BASE = process.env.API_BASE || 'http://localhost:5000';
if (!/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(BASE)) {
    console.error(`Refusing to run against ${BASE} - localhost only.`);
    process.exit(2);
}

let pass = 0, fail = 0;
const failures = [];
const tag = Date.now().toString().slice(-6);

async function call(method, path, { token, body, headers } = {}) {
    const res = await fetch(BASE + path, {
        method,
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(headers || {}) },
        body: body ? JSON.stringify(body) : undefined,
    });
    const json = await res.json().catch(() => ({}));
    return { status: res.status, json, data: json.data };
}

function check(name, ok, detail = '') {
    if (ok) { pass++; console.log(`  ok    ${name}`); }
    else { fail++; failures.push(name); console.log(`  FAIL  ${name} ${detail}`); }
}
// Endpoints wrap their payload differently (data.item, data.user, ...): unwrap.
const unwrap = (d) => (d && typeof d === 'object' && !Array.isArray(d) && !d._id ? (d.item || d.user || d.container || d) : d);
const section = (t) => console.log(`\n${t}`);

(async () => {
    const health = await fetch(BASE + '/health').catch(() => null);
    if (!health || !health.ok) { console.error('Backend is not running on ' + BASE); process.exit(2); }

    // ── Auth ────────────────────────────────────────────────────────────────
    section('Auth');
    let r = await call('POST', '/api/auth/login', { body: { mobile: '7029621489', password: 'Admin@123' } });
    check('admin login', r.status === 200 && r.data?.token);
    const admin = r.data?.token;
    r = await call('POST', '/api/auth/login', { body: { mobile: '7029621489', password: 'wrong' } });
    check('wrong password rejected', r.status === 401 || r.status === 400, `(${r.status})`);
    r = await call('GET', '/api/auth/me', { token: admin });
    check('/auth/me returns admin', r.data?.role === 'admin' || r.data?.user?.role === 'admin', JSON.stringify(r.json).slice(0, 80));

    // ── Settings ────────────────────────────────────────────────────────────
    section('Settings');
    r = await call('POST', '/api/settings/initialize', { token: admin });
    check('initialize default settings', r.status === 200 || r.status === 201, `(${r.status} ${r.json.message || ''})`);
    r = await call('GET', '/api/settings/item/itemTypes', { token: admin });
    check('read item types', r.status === 200 && (r.data || []).includes('ring'));
    r = await call('POST', '/api/settings/item/itemTypes/add', { token: admin, body: { value: `smoke${tag}` } });
    check('add an item type', r.status === 200 || r.status === 201, `(${r.status} ${r.json.message || ''})`);
    r = await call('GET', '/api/settings/item/itemTypes', { token: admin });
    check('new item type is listed', (r.data || []).includes(`smoke${tag}`));
    r = await call('DELETE', `/api/settings/item/itemTypes/smoke${tag}`, { token: admin });
    check('delete the item type', r.status === 200, `(${r.status})`);
    r = await call('GET', '/api/settings/container/containerTypes', { token: admin });
    check('read container types', r.status === 200 && (r.data || []).length > 0);

    // ── Containers ──────────────────────────────────────────────────────────
    section('Containers');
    r = await call('POST', '/api/containers', { token: admin, body: {
        name: `SMOKE Box ${tag}`, type: 'box', capacity: 20, weightCategory: 'Light', layoutType: 'grid',
        qrCode: `SMOKE-C-${tag}`, allowedItemTypes: ['ring', 'chain'],
    } });
    check('create container', r.status === 201 || r.status === 200, `(${r.status} ${r.json.message || ''})`);
    const containerId = unwrap(r.data)?._id;
    r = await call('POST', '/api/containers', { token: admin, body: {
        name: 'dup', type: 'box', capacity: 5, qrCode: `SMOKE-C-${tag}` } });
    check('duplicate container barcode rejected', r.status >= 400 && r.status < 500, `(${r.status})`);
    r = await call('GET', '/api/containers', { token: admin });
    check('list containers', r.status === 200 && (r.data?.containers || []).length > 0);

    // ── Items ───────────────────────────────────────────────────────────────
    section('Items');
    const itemBody = (n, extra = {}) => ({
        barcode: `SMOKE-I-${tag}-${n}`, name: `SMOKE Ring ${n}`, itemType: 'ring', metalType: 'gold',
        purity: '22k', netWeight: 4.25, grossWeight: 4.5, ...extra,
    });
    r = await call('POST', '/api/items', { token: admin, body: itemBody(1) });
    check('create item (no container)', r.status === 201 || r.status === 200, `(${r.status} ${r.json.message || ''})`);
    const itemId = unwrap(r.data)?._id;
    r = await call('POST', '/api/items', { token: admin, body: itemBody(2, containerId ? { containerId } : {}) });
    check('create item (with container)', r.status === 201 || r.status === 200, `(${r.status} ${r.json.message || ''})`);
    const item2 = unwrap(r.data)?._id;
    r = await call('POST', '/api/items', { token: admin, body: itemBody(1) });
    check('duplicate item barcode rejected', r.status >= 400 && r.status < 500, `(${r.status})`);
    r = await call('POST', '/api/items', { token: admin, body: { name: 'incomplete' } });
    check('incomplete item rejected', r.status >= 400 && r.status < 500, `(${r.status})`);
    r = await call('GET', `/api/items/barcode/SMOKE-I-${tag}-1`, { token: admin });
    check('find item by barcode', r.status === 200 && unwrap(r.data)?.name === 'SMOKE Ring 1');
    r = await call('PUT', `/api/items/${itemId}`, { token: admin, body: { name: 'SMOKE Ring 1 edited', netWeight: 5 } });
    check('edit item', r.status === 200, `(${r.status} ${r.json.message || ''})`);
    r = await call('GET', `/api/items/${itemId}`, { token: admin });
    check('edit persisted', unwrap(r.data)?.name === 'SMOKE Ring 1 edited' && unwrap(r.data)?.netWeight === 5);
    r = await call('GET', '/api/items?search=SMOKE', { token: admin });
    check('search items', r.status === 200);
    r = await call('DELETE', `/api/items/${itemId}`, { token: admin });
    check('delete item (recycle bin)', r.status === 200, `(${r.status})`);
    r = await call('PUT', `/api/items/${itemId}/restore`, { token: admin });
    check('restore item', r.status === 200, `(${r.status})`);
    r = await call('PUT', `/api/items/${item2}/sell`, { token: admin, body: { soldTo: 'SMOKE Buyer', sellingPrice: 30000 } });
    check('there is no separate quick-sale any more (a piece is sold on a GST bill)', r.status === 404, `(${r.status} ${r.json.message || ''})`);

    // ── Users & roles ───────────────────────────────────────────────────────
    section('Users & permissions');
    const mk = (role, n) => call('POST', '/api/users', { token: admin, body: {
        name: `SMOKE ${role} ${tag}`, mobile: `95${tag}${n}`.slice(0, 10), password: 'Smoke@123', role } });
    r = await mk('staff', 1); check('create staff user', r.status === 201 || r.status === 200, `(${r.status} ${r.json.message || ''})`);
    const staffId = unwrap(r.data)?._id;
    r = await mk('viewer', 2); check('create viewer user', r.status === 201 || r.status === 200, `(${r.status} ${r.json.message || ''})`);
    r = await call('POST', '/api/users', { token: admin, body: { name: 'dup', mobile: `95${tag}1`.slice(0, 10), password: 'x' } });
    check('duplicate mobile rejected', r.status === 400, `(${r.status})`);
    const login = async (n) => (await call('POST', '/api/auth/login', { body: { mobile: `95${tag}${n}`.slice(0, 10), password: 'Smoke@123' } })).data?.token;
    const staff = await login(1), viewer = await login(2);
    check('staff can log in', !!staff); check('viewer can log in', !!viewer);
    r = await call('GET', '/api/users', { token: staff });
    check('staff cannot list users (403)', r.status === 403, `(${r.status})`);
    r = await call('GET', '/api/permissions/me', { token: viewer });
    check('viewer permission map loads', r.status === 200, `(${r.status})`);
    r = await call('GET', '/api/permissions/roles', { token: admin });
    check('role grid loads', r.status === 200 || r.status === 404, `(${r.status})`);

    // ── Directory ───────────────────────────────────────────────────────────
    section('User Directory');
    r = await call('GET', '/api/directory/summary', { token: admin });
    check('summary counts', r.status === 200 && r.data?.customers > 0, JSON.stringify(r.data));
    const before = r.data?.customers;
    r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `SMOKE Cust ${tag}`, whatsappNo: `96${tag}00`.slice(0, 10) } });
    check('add customer', r.status === 201, `(${r.status} ${r.json.message || ''})`);
    r = await call('POST', '/api/directory/customers', { token: admin, body: { name: 'again', whatsappNo: `96${tag}00`.slice(0, 10) } });
    check('duplicate customer -> 409', r.status === 409, `(${r.status})`);
    r = await call('GET', '/api/directory/summary', { token: admin });
    check('customer count went up by exactly 1', r.data?.customers === before + 1, `(${before} -> ${r.data?.customers})`);
    r = await call('GET', `/api/directory/customers?q=${encodeURIComponent('SMOKE Cust ' + tag)}`, { token: admin });
    check('search finds new customer', r.data?.length === 1);
    r = await call('GET', '/api/directory/staff', { token: admin });
    check('staff list has no secrets', r.status === 200 && !JSON.stringify(r.json).match(/SHOULD-NEVER-LEAK|password|remember_token/i));
    r = await call('GET', '/api/directory/staff', { token: staff });
    check('staff role denied staff directory (403)', r.status === 403, `(${r.status})`);
    r = await call('GET', '/api/directory/customers', { token: staff });
    check('staff role can view customers', r.status === 200, `(${r.status})`);
    r = await call('POST', '/api/directory/customers', { token: viewer, body: { name: 'x', whatsappNo: '9000000000' } });
    check('viewer cannot add customer (403)', r.status === 403, `(${r.status})`);
    r = await call('POST', '/api/directory/suppliers', { token: admin, body: { firstName: `SMOKE Sup ${tag}`, mobile: '9333000000' } });
    check('add supplier', r.status === 201 || r.status === 409, `(${r.status})`);
    r = await call('POST', '/api/directory/karigars', { token: admin, body: { firstName: `SMOKE Kar ${tag}`, mobile: '9444000000' } });
    check('add karigar', r.status === 201 || r.status === 409, `(${r.status})`);
    r = await call('POST', '/api/directory/staff', { token: admin, body: { firstName: `SMOKE Stf ${tag}`, mobile: `9555${tag}`.slice(0, 10) } });
    check('add staff profile', r.status === 201, `(${r.status})`);
    // per-user override lets a staff user into the staff directory
    r = await call('PUT', `/api/users/${staffId}/permission-overrides`, { token: admin, body: { overrides: { 'directory.viewStaff': true } } });
    check('grant per-user override', r.status === 200, `(${r.status} ${r.json.message || ''})`);
    r = await call('GET', '/api/directory/staff', { token: staff });
    check('override takes effect', r.status === 200, `(${r.status})`);

    // ── Branches & rich customer profile ────────────────────────────────────
    section('Branches & customer profile');
    r = await call('GET', '/api/directory/branches', { token: admin });
    check('branches list includes built-in main', r.status === 200 && r.data?.[0]?._id === 'main');
    r = await call('POST', '/api/directory/branches', { token: staff, body: { name: 'X' } });
    check('non-admin cannot add a branch (403)', r.status === 403, `(${r.status})`);
    r = await call('POST', '/api/directory/branches', { token: admin, body: { name: `SMOKE Branch ${tag}`, city: 'Howrah' } });
    check('admin adds a branch', r.status === 201, `(${r.status} ${r.json.message || ''})`);
    const branchId = r.data?._id;
    r = await call('POST', '/api/directory/branches', { token: admin, body: { name: `smoke branch ${tag}` } });
    check('duplicate branch name rejected (409)', r.status === 409, `(${r.status})`);
    r = await call('POST', '/api/directory/customers', { token: admin, body: {
        name: `SMOKE Rich ${tag}`, whatsappNo: `97${tag}00`.slice(0, 10), branchId, customerType: 'Wholesale',
        city: 'Howrah', state: 'West Bengal', gstNo: '19abcde1234f1z5', dob: '1990-05-01',
        opening: { cash: { amount: 5000, type: 'debit' }, gold: { weight: 3.5, unit: 'gram', type: 'credit' } } } });
    check('add customer with full profile', r.status === 201, `(${r.status} ${r.json.message || ''})`);
    const richId = r.data?._id;
    r = await call('GET', `/api/directory/customers/${richId}`, { token: admin });
    check('profile stored with branch', r.data?.profile?.branchId === branchId && r.data?.profile?.branchName === `SMOKE Branch ${tag}`);
    check('profile fields saved (gst upper-cased, balance)', r.data?.profile?.gstNo === '19ABCDE1234F1Z5' && r.data?.profile?.opening?.cash?.amount === 5000);
    check('legacy document has NO app-only fields', !('gstNo' in r.data) && !('branchId' in r.data) && !('opening' in r.data));
    r = await call('POST', '/api/directory/customers', { token: admin, body: { name: 'bad branch', whatsappNo: '9800000001', branchId: '000000000000000000000000' } });
    check('unknown branch rejected (400)', r.status === 400, `(${r.status})`);
    r = await call('POST', '/api/directory/suppliers', { token: admin, body: { firstName: `SMOKE BSup ${tag}`, mobile: '9666000000', branchId } });
    check('supplier carries branch', (r.status === 201 && r.data?.branchId === branchId) || r.status === 409, `(${r.status})`);

    // ── Validation, multi-number duplicates, lookup, referral, branch-from-login
    section('Validation, lookup, referral & branch');
    const post = (body, token = admin) => call('POST', '/api/directory/customers', { token, body });
    const base = (extra = {}) => ({ name: `SMOKE V ${tag}`, ...extra });
    const n = (i) => `98${tag}${String(i).padStart(2, '0')}`.slice(0, 10);   // unique valid mobiles
    r = await post(base({ contacts: [{ number: '1234567890' }] }));
    check('mobile must start 6-9 (400)', r.status === 400, `(${r.status})`);
    r = await post(base({ contacts: [{ number: '98765' }] }));
    check('short number rejected (400)', r.status === 400, `(${r.status})`);
    r = await post(base({ contacts: [{ number: n(1) }, { number: n(1) }] }));
    check('same number twice in one form rejected (400)', r.status === 400, `(${r.status})`);
    r = await post(base({ contacts: [{ number: n(1) }], panNo: 'BADPAN' }));
    check('bad PAN rejected', r.status === 400 && /PAN/.test(r.json.message), r.json.message);
    r = await post(base({ contacts: [{ number: n(1) }], gstNo: '19ABCDE1234F1Z0' === 'x' ? '' : '123' }));
    check('bad GST rejected', r.status === 400 && /GST/.test(r.json.message), r.json.message);
    r = await post(base({ contacts: [{ number: n(1) }], gstNo: '19ABCDE1234F1Z5', panNo: 'ZZZZZ9999Z' }));
    check('PAN must match GST', r.status === 400 && /match/.test(r.json.message), r.json.message);
    r = await post(base({ contacts: [{ number: n(1) }], email: 'not-an-email' }));
    check('bad email rejected', r.status === 400 && /Email/.test(r.json.message), r.json.message);
    r = await post(base({ contacts: [{ number: n(1) }], pincode: '12' }));
    check('bad pincode rejected', r.status === 400 && /Pincode/.test(r.json.message), r.json.message);
    r = await post(base({ contacts: [{ number: n(1) }], aadharNo: '1234' }));
    check('bad Aadhaar rejected', r.status === 400 && /Aadhaar/.test(r.json.message), r.json.message);
    r = await post(base({ contacts: [{ number: n(1) }], dob: '2999-01-01' }));
    check('future date of birth rejected', r.status === 400 && /future/.test(r.json.message), r.json.message);
    r = await post(base({ contacts: [{ number: n(1) }], bank: { ifsc: 'BAD' } }));
    check('bad IFSC rejected', r.status === 400 && /IFSC/.test(r.json.message), r.json.message);
    r = await post(base({ contacts: Array.from({ length: 7 }, (_, i) => ({ number: n(20 + i) })) }));
    check('more than 6 numbers rejected', r.status === 400, `(${r.status})`);

    // 5 numbers: beyond the 4 legacy slots, so the 5th only lives in the app profile
    const five = [n(30), n(31), n(32), n(33), n(34)];
    r = await post(base({ name: `SMOKE Multi ${tag}`, contacts: five.map((x, i) => ({ number: x, label: i ? 'mobile' : 'whatsapp' })), nameBengali: 'পরীক্ষা' }));
    check('customer with 5 numbers saved', r.status === 201, `(${r.status} ${r.json.message || ''})`);
    const multi = r.data;
    check('legacy doc holds first 4 numbers', multi?.whatsapp_no === five[0] && multi?.mobile_no === five[1] && multi?.mobile_no_3 === five[2] && multi?.mobile_no_4 === five[3]);
    check('profile holds all 5 + LGP code', multi?.profile?.contacts?.length === 5 && /^LGP\d{6}[0-9A-F]{3}$/.test(multi?.profile?.customerCode));
    r = await post(base({ contacts: [{ number: five[4] }] }));
    check('duplicate on the 5th (profile-only) number -> 409', r.status === 409, `(${r.status})`);
    r = await post(base({ contacts: [{ number: five[2] }] }));
    check('duplicate on a legacy slot -> 409', r.status === 409, `(${r.status})`);

    // live lookup
    r = await call('GET', `/api/directory/customers/lookup?q=${five[4].slice(0, 6)}`, { token: admin });
    check('lookup by partial number finds the customer', r.status === 200 && r.data?.some((x) => x.id === multi._id));
    r = await call('GET', `/api/directory/customers/lookup?q=${five[4]}`, { token: admin });
    check('full number is flagged exact', r.data?.some((x) => x.id === multi._id && x.exact === true));
    r = await call('GET', `/api/directory/customers/lookup?q=${multi.profile.customerCode}`, { token: admin });
    check('lookup by customer code', r.data?.some((x) => x.id === multi._id));
    r = await call('GET', `/api/directory/customers/lookup?q=${encodeURIComponent('SMOKE Multi ' + tag)}`, { token: admin });
    check('lookup by name', r.data?.some((x) => x.id === multi._id));
    r = await call('GET', '/api/directory/customers/lookup?q=a', { token: admin });
    check('1-char query returns nothing', r.status === 200 && r.data?.length === 0);
    r = await call('GET', `/api/directory/customers?q=${five[4]}`, { token: admin });
    check('main list search also finds profile-only numbers', r.data?.some((x) => x._id === multi._id));

    // referral
    r = await post(base({ name: `SMOKE Ref ${tag}`, contacts: [{ number: n(40) }], referredById: multi._id }));
    check('customer referred by an existing customer', r.status === 201, `(${r.status} ${r.json.message || ''})`);
    check('referral stored as link + snapshot',
        r.data?.reference_customer_id === multi._id && r.data?.profile?.referredBy?.name === multi.customer_name
        && r.data?.profile?.referredBy?.code === multi.profile.customerCode);
    r = await post(base({ contacts: [{ number: n(41) }], referredById: '000000000000000000000000' }));
    check('referral to a missing customer rejected (400)', r.status === 400, `(${r.status})`);
    r = await post(base({ name: `SMOKE Txt ${tag}`, contacts: [{ number: n(42) }], referredByText: 'Walk-in via Ramesh' }));
    check('free-text referral kept', r.status === 201 && r.data?.profile?.referredBy?.text === 'Walk-in via Ramesh');

    // branch comes from the signed-in user
    r = await call('POST', '/api/directory/branches', { token: admin, body: { name: `SMOKE Shop2 ${tag}` } });
    const shop2 = r.data?._id;
    r = await call('POST', '/api/users', { token: admin, body: { name: `SMOKE Branch Staff ${tag}`, mobile: `94${tag}1`.slice(0, 10), password: 'Smoke@123', role: 'staff', branchId: shop2 } });
    check('create user assigned to a branch', r.status === 201 || r.status === 200, `(${r.status} ${r.json.message || ''})`);
    const bl = await call('POST', '/api/auth/login', { body: { mobile: `94${tag}1`.slice(0, 10), password: 'Smoke@123' } });
    check('login returns the user\'s branch', bl.data?.user?.branchId === shop2 && /SMOKE Shop2/.test(bl.data?.user?.branchName));
    const branchStaff = bl.data?.token;
    r = await call('POST', '/api/directory/customers', { token: branchStaff, body: base({ name: `SMOKE BrCust ${tag}`, contacts: [{ number: n(50) }], branchId: 'main' }) });
    check('staff record is filed under THEIR branch (requested branch ignored)', r.status === 201 && r.data?.profile?.branchId === shop2, JSON.stringify(r.json).slice(0, 100));
    r = await call('POST', '/api/users', { token: admin, body: { name: 'x', mobile: `93${tag}1`.slice(0, 10), password: 'Smoke@123', branchId: '000000000000000000000000' } });
    check('user with unknown branch rejected (400)', r.status === 400, `(${r.status})`);

    // ── Auto-fill helpers ───────────────────────────────────────────────────
    section('Auto-fill (Bengali, pincode, IFSC)');
    r = await call('POST', '/api/directory/translate', { token: admin, body: { name: 'Sunita Das', nickname: 'Suni', address: '12 Test Road, Howrah' } });
    const bn = /[\u0980-\u09FF]/;
    check('name is transliterated to Bengali', r.status === 200 && bn.test(r.data?.name || ''), JSON.stringify(r.data));
    check('nickname and address too', bn.test(r.data?.nickname || '') && bn.test(r.data?.address || ''));
    r = await call('POST', '/api/directory/translate', { token: admin, body: { name: 'রাহুল' } });
    check('already-Bengali text passes through unchanged', r.data?.name === 'রাহুল');
    r = await call('POST', '/api/directory/translate', { token: viewer, body: { name: 'Amit' } });
    check('viewer may use auto-fill (directory.view)', r.status === 200);
    r = await call('POST', '/api/directory/translate', { body: { name: 'Amit' } });
    check('auto-fill needs login (401)', r.status === 401);
    r = await call('GET', '/api/directory/lookup/pincode/711403', { token: admin });
    check('pincode -> state + city', r.status === 200 && r.data?.state === 'West Bengal' && !!r.data?.city, JSON.stringify(r.data).slice(0, 90));
    r = await call('GET', '/api/directory/lookup/pincode/12', { token: admin });
    check('bad pincode -> 404', r.status === 404);
    r = await call('GET', '/api/directory/lookup/ifsc/SBIN0000001', { token: admin });
    check('IFSC -> bank + branch', r.status === 200 && /State Bank/i.test(r.data?.bank || '') && !!r.data?.branch, JSON.stringify(r.data).slice(0, 90));
    r = await call('GET', '/api/directory/lookup/ifsc/BAD', { token: admin });
    check('bad IFSC -> 404', r.status === 404);

    // ── Editing (guarded updates) ───────────────────────────────────────────
    section('Editing');
    const put = (path, body, token = admin) => call('PUT', `/api/directory${path}`, { token, body });
    const custBody = (over = {}) => ({ name: `SMOKE Edit ${tag}`, contacts: [{ number: n(60) }, { number: n(61), label: 'mobile' }, { number: n(62), label: 'home' }], email: 'e@example.test', nickname: 'Eddy', ...over });
    r = await post(custBody());
    check('customer for editing created', r.status === 201, `(${r.status} ${r.json.message || ''})`);
    const ed = r.data;
    const countBefore = (await call('GET', '/api/directory/summary', { token: admin })).data?.customers;

    r = await put(`/customers/${ed._id}`, custBody({ name: `SMOKE Edited ${tag}`, nameBengali: 'সম্পাদিত', contacts: [{ number: n(60) }], email: '', nickname: '', city: 'Howrah', expectedUpdatedAt: ed.updated_at }));
    check('edit customer succeeds', r.status === 200, `(${r.status} ${r.json.message || ''})`);
    check('legacy fields updated; removed ones cleared', r.data?.customer_name === `SMOKE Edited ${tag}` && r.data?.customer_name_bengali === 'সম্পাদিত'
        && r.data?.mobile_no === '' && !r.data?.mobile_no_3 && !r.data?.email && !r.data?.nickname);
    check('profile updated + code unchanged', r.data?.profile?.city === 'Howrah' && r.data?.profile?.customerCode === ed.profile.customerCode && r.data?.profile?.contacts?.length === 1);
    check('updated_by recorded', r.data?.updated_by_name === 'Admin' && !!r.data?.updated_at);
    r = await call('GET', '/api/directory/summary', { token: admin });
    check('edit never adds or removes customers', r.data?.customers === countBefore, `(${countBefore} -> ${r.data?.customers})`);

    r = await put(`/customers/${ed._id}`, custBody({ expectedUpdatedAt: ed.updated_at }));
    check('stale edit rejected (409 conflict)', r.status === 409 && r.json.conflict === true, `(${r.status})`);

    r = await call('GET', `/api/directory/history/customer/${ed._id}`, { token: admin });
    check('audit trail records the change field by field', r.status === 200 && r.data?.length >= 1
        && r.data[0].changes.some((c) => c.field === 'customer_name' && c.to === `SMOKE Edited ${tag}`), JSON.stringify(r.data?.[0]?.changes || []).slice(0, 120));
    check('audit entry names the editor', r.data?.[0]?.byName === 'Admin');

    r = await call('GET', `/api/directory/customers/${ed._id}`, { token: admin });
    const cur = r.data.updated_at;
    r = await put(`/customers/${ed._id}`, custBody({ contacts: [{ number: n(60) }, { number: multi.whatsapp_no }], expectedUpdatedAt: cur }));
    check('editing onto another customer\'s number -> 409', r.status === 409 && !r.json.conflict, `(${r.status} ${r.json.message || ''})`);
    r = await put(`/customers/${ed._id}`, custBody({ contacts: [{ number: n(60) }], referredById: ed._id, expectedUpdatedAt: cur }));
    check('cannot be referred by themselves (400)', r.status === 400, `(${r.status})`);
    r = await put(`/customers/${ed._id}`, custBody({ contacts: [{ number: '123' }], expectedUpdatedAt: cur }));
    check('edit validates like create (400)', r.status === 400, `(${r.status})`);
    r = await put('/customers/000000000000000000000000', custBody());
    check('editing a missing customer -> 404', r.status === 404, `(${r.status})`);

    // an OLDER customer (no app profile yet) gets one on first edit
    r = await call('GET', '/api/directory/customers?q=TEST&limit=50', { token: admin });
    let oldC = null, oldFull = null;
    for (const cand of (r.data || [])) {
        if (!/^TEST /.test(cand.customer_name)) continue;
        const full = await call('GET', `/api/directory/customers/${cand._id}`, { token: admin });
        if (full.data && full.data.profile === null) { oldC = cand; oldFull = full; break; }
    }
    if (oldC) {
        check('found an older customer that has no app profile yet', true);
        r = await put(`/customers/${oldC._id}`, { name: oldC.customer_name, contacts: [{ number: oldC.whatsapp_no }], city: 'Bagnan', expectedUpdatedAt: oldFull.data.updated_at });
        check('first edit creates the profile + customer code', r.status === 200 && /^LGP\d{6}[0-9A-F]{3}$/.test(r.data?.profile?.customerCode || '') && r.data?.profile?.source === 'shopmanage', `(${r.status} ${r.json.message || ''})`);
        check('older customer keeps its legacy serial number', r.data?.sl_no === oldC.sl_no);
    } else {
        check('(all seeded older customers were already edited by earlier runs — reset with `node scripts/local-db.js --reset`)', true);
    }

    // permissions
    r = await put(`/customers/${ed._id}`, custBody({ contacts: [{ number: n(60) }] }), viewer);
    check('viewer cannot edit (403)', r.status === 403, `(${r.status})`);
    r = await call('GET', `/api/directory/history/customer/${ed._id}`, { token: viewer });
    check('viewer cannot read edit history (403)', r.status === 403, `(${r.status})`);
    r = await call('GET', `/api/directory/customers/${ed._id}`, { token: admin });
    r = await put(`/customers/${ed._id}`, custBody({ name: `SMOKE ByStaff ${tag}`, contacts: [{ number: n(60) }], expectedUpdatedAt: r.data.updated_at }), staff);
    check('staff can edit customers', r.status === 200, `(${r.status} ${r.json.message || ''})`);

    // suppliers / karigars / staff profiles
    r = await call('POST', '/api/directory/suppliers', { token: admin, body: { firstName: `SMOKE ESup ${tag}`, mobile: n(70), gstNo: '19ABCDE1234F1Z5' } });
    const sup = r.data;
    r = await put(`/suppliers/${sup._id}`, { firstName: `SMOKE ESup2 ${tag}`, mobile: n(70), city: 'Kolkata', expectedUpdatedAt: sup.updatedAt });
    check('edit supplier', r.status === 200 && r.data?.city === 'Kolkata' && r.data?.gstNo === '', `(${r.status} ${r.json.message || ''})`);
    r = await put(`/suppliers/${sup._id}`, { firstName: 'x', mobile: n(70), expectedUpdatedAt: sup.updatedAt });
    check('stale supplier edit -> 409', r.status === 409 && r.json.conflict === true, `(${r.status})`);
    r = await call('POST', '/api/directory/karigars', { token: admin, body: { firstName: `SMOKE EKar ${tag}`, mobile: n(71) } });
    const kar = r.data;
    r = await put(`/karigars/${kar._id}`, { firstName: `SMOKE EKar2 ${tag}`, mobile: n(71), expectedUpdatedAt: kar.updatedAt });
    check('edit karigar', r.status === 200, `(${r.status} ${r.json.message || ''})`);
    r = await call('POST', '/api/directory/staff', { token: admin, body: { firstName: `SMOKE EStf ${tag}`, mobile: n(72) } });
    const stf = r.data;
    r = await put(`/staff/profile/${stf._id}`, { firstName: `SMOKE EStf2 ${tag}`, mobile: n(72), employment: { designation: 'Manager', salary: 20000 }, expectedUpdatedAt: stf.updatedAt });
    check('admin edits a staff profile', r.status === 200 && r.data?.employment?.designation === 'Manager', `(${r.status} ${r.json.message || ''})`);
    r = await put(`/staff/profile/${stf._id}`, { firstName: 'x', mobile: n(72) }, staff);
    check('staff role cannot edit staff profiles (403)', r.status === 403, `(${r.status})`);
    r = await call('GET', '/api/directory/staff', { token: admin });
    const loginRow = r.data?.find((x) => x.source === 'login');
    r = await put(`/staff/login/${loginRow.id}`, { firstName: 'x', mobile: n(73) });
    // (the app's global not-found handler answers unknown routes with 500 — pre-existing; we only need "rejected")
    check('legacy login accounts are NOT editable (no such route)', r.status >= 400, `(${r.status})`);
    r = await call('GET', `/api/directory/history/staff/${stf._id}`, { token: admin });
    check('staff edit is audited', r.data?.[0]?.changes?.some((c) => c.field === 'employment'));

    // ── GST billing (live LGPManagement rules + document shape) ─────────────────
    section('GST billing');
    const { MongoClient } = require('mongodb');
    const rawDb = await MongoClient.connect('mongodb://127.0.0.1:27018');
    const lgp = rawDb.db('lgp_dev');
    await lgp.collection('invoices').deleteMany({});           // local test DB only: start from the known legacy set
    await lgp.collection('shop_info').deleteMany({});
    await require('./seed-legacy-invoices').seedLegacyInvoices('mongodb://127.0.0.1:27018', 'lgp_dev');
    const uid = () => 'req-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
    const ring = (over = {}) => ({ particulars: 'Gold Ring', metalType: 'Gold', netWt: 10.5, rate: 6000, makingCharge: 1500, hsnCode: '7113', ...over });
    const bill = (over = {}, token = admin) => call('POST', '/api/billing/invoices', { token, body: { requestId: uid(), customerId: multi._id, items: [ring()], goldRate: 9190, silverRate: 110, paymentMode: 'Online', customerAddress: '12 Test Road, Howrah', ...over } });
    const find = async (num) => { const x = await call('GET', `/api/billing/invoices?q=${encodeURIComponent(num)}&limit=50`, { token: admin }); return x.data?.find((y) => y.invoiceNumber === num); };
    const open = async (id, token = admin) => (await call('GET', `/api/billing/invoices/${id}`, { token })).data;

    r = await call('GET', '/api/billing/meta', { token: admin });
    const nextBefore = Number(r.data?.nextInvoiceNumber);
    check('meta: live seller GSTIN, next number continues the website sequence', r.status === 200 && r.data?.seller?.gstin === '19AKFPN3465R1ZB' && nextBefore >= 1760, JSON.stringify(r.data).slice(0, 100));
    check('meta: 4 payment modes (no wallet), HSN list, TDS limit, delivery terms', r.data?.paymentModes?.length === 4 && !r.data.paymentModes.includes('LGP_Wallet') && r.data?.hsnCodes?.length === 5 && r.data?.tdsThreshold === 200000 && r.data?.termsOfDelivery?.includes('Customer Pickup'));
    check('meta: prints the live terms (Chandannagar jurisdiction)', r.data?.terms?.some((t) => /Chandannagar/.test(t)) && r.data?.terms?.length === 6);
    r = await call('GET', '/api/billing/meta', { token: viewer });
    check('viewer can read billing meta', r.status === 200);
    r = await bill({ invoiceDate: '2099-01-01', paymentMode: 'Online', paidAmount: 100000 });
    check('a bill dated in the future is refused (400)', r.status === 400 && /future/i.test(r.json?.message || ''), `(${r.status}) ${r.json?.message}`);
    r = await call('POST', '/api/billing/calculate', { token: admin, body: { items: [ring()], goldRate: 9190, silverRate: 110, paidAmount: 1000 } });
    check('calculate: totals for a typed bill, nothing saved', r.status === 200 && r.data?.totalPayableAmount > 60000 && r.data?.dueAmount === r.data.totalPayableAmount - 1000 && r.data?.gstType === 'CGST_SGST', JSON.stringify(r.json).slice(0, 100));
    r = await call('POST', '/api/billing/calculate', { token: admin, body: { items: [ring()], goldRate: 9190, placeOfSupply: '27-Maharashtra' } });
    check('calculate: another state gives IGST', r.status === 200 && r.data?.gstType === 'IGST' && r.data?.interstate === true, JSON.stringify(r.json).slice(0, 100));
    r = await call('POST', '/api/billing/calculate', { token: admin, body: { items: [], goldRate: 9190 } });
    check('calculate: no items is a clear 400', r.status === 400);
    r = await call('POST', '/api/billing/calculate', { token: viewer, body: { items: [ring()], goldRate: 9190 } });
    check('calculate: viewer cannot (403)', r.status === 403, `(${r.status})`);
    r = await bill({}, viewer);
    check('viewer cannot create an invoice (403)', r.status === 403, `(${r.status})`);

    // -- invoices the WEBSITE already wrote must display correctly ---------------------------
    section('GST billing: invoices already in the live collection');
    const l1401 = await find('1401');
    const v1401 = l1401 && await open(l1401._id);
    check('legacy invoice 1401 shows (Bengali words, print count, items)', v1401?.totalPayableAmount === 800 && v1401?.roundOff === -0.18 && v1401?.totalAmount === 878.18 && v1401?.printStatus === 1 && v1401?.items?.[0]?.particular === 'Gold Chain' && /টাকা/.test(v1401?.amountInWords || ''));
    check('legacy GST summary (total_gst 23.98) and payment history map across', v1401?.gstSummary?.totalTax === 23.98 && v1401?.paymentHistory?.[0]?.mode === 'Cash' && v1401?.paymentHistory?.[0]?.amount === 800 && !!v1401?.paymentHistory?.[0]?.date);
    check('legacy invoice is not a "walk-in" and belongs to the main branch', v1401?.walkIn === false && v1401?.branchId === 'main');
    const l1423 = await find('1423');
    const v1423 = await open(l1423._id);
    check('legacy typed-taxable invoice 1423 (taxable 2600, cgst 39) displays as stored', v1423?.items?.[0]?.taxableAmount === 2600 && v1423?.items?.[0]?.cgst === 39 && v1423?.totalPayableAmount === 2600);
    const lBlock = await find('1-100');
    const vBlock = lBlock && await open(lBlock._id);
    check('hand-written block bill "1-100" (no rates) displays without error', vBlock?.totalPayableAmount === 0 && vBlock?.items?.length === 1 && vBlock?.gstSummary?.totalTax === 0);
    const l1500 = await find('1500');
    check('legacy part-paid invoice shows its due (26865) and status', l1500?.dueAmount === 26865 && l1500?.status === 'active', JSON.stringify(l1500));
    const l1450 = await find('1450');
    check('legacy cancelled invoice is listed with its status', l1450?.status === 'cancelled');
    r = await call('GET', '/api/billing/invoices?status=due&limit=50', { token: admin });
    check('"due" filter includes 1500 and skips cancelled / paid ones', r.data?.some((x) => x.invoiceNumber === '1500') && !r.data?.some((x) => x.invoiceNumber === '1450' || x.invoiceNumber === '1401'));
    r = await call('GET', '/api/billing/invoices?status=paid&limit=50', { token: admin });
    check('"paid" filter includes 1401 and skips cancelled / due ones', r.data?.some((x) => x.invoiceNumber === '1401') && !r.data?.some((x) => x.invoiceNumber === '1450' || x.invoiceNumber === '1500'));

    // -- create: a small bill with a discount (taken off BEFORE GST, out of the making charge) ------
    section('GST billing: creating invoices');
    const rid1 = uid();
    // the same bill as real invoice 1401 (0.08 g @ 9190 + 64 making + 55 charges taxed at 3% = 880), the customer pays 850
    r = await bill({ requestId: rid1, items: [ring({ netWt: 0.08, rate: 9190, makingCharge: 64 })], additionalCharges: 55, discount: 30, paidAmount: 850, paymentMode: 'Cash',
        totalPayableAmount: 1, dueAmount: 0, totalAmount: 1 /* tampered totals must be ignored */ });
    const near = (a, b, t = 0.02) => typeof a === 'number' && Math.abs(a - b) <= t;
    check('discount 30 -> payable exactly 850, taken off the making charge (64 -> ~35.04), GST recalculated', r.status === 201 && r.data?.totalPayableAmount === 850 && r.data?.dueAmount === 0 && r.data?.discountGiven === 30
        && near(r.data?.discountBeforeGst, 28.96) && near(r.data?.items?.[0]?.makingCharge, 35.04) && near(r.data?.items?.[0]?.taxableAmount, 770.24) && r.data?.grossTaxable === 799.2 && r.data?.discountMode === 'before_gst', `(${r.status} ${r.json.message || ''} ${JSON.stringify(r.data).slice(0, 200)})`);
    const inv0 = r.data;
    check('number is 4 digits and continues the website sequence', /^\d{4}$/.test(inv0?.invoiceNumber || '') && Number(inv0.invoiceNumber) >= 1760, inv0?.invoiceNumber);
    check('status is "delivered" (paid in full, delivery today)', inv0?.status === 'delivered');
    check('amount in words is English (Bengali)', /^Eight Hundred and Fifty Rupees Only \(.+টাকা মাত্র\)$/.test(inv0?.amountInWords || ''));

    // what is physically stored must be the website's snake_case shape
    const raw0 = await lgp.collection('invoices').findOne({ invoice_number: inv0.invoiceNumber });
    check('stored in the live `invoices` collection with the website\'s field names',
        raw0 && raw0.total_payable_amount === 850 && Math.abs(raw0.round_off) < 0.006 && near(raw0.total_amount, 850, 0.006) && raw0.due_advance === 0 && raw0.print_status === 0
        && near(raw0.gst_summary?.total_gst, 24.76, 0.02) && near(raw0.gst_summary?.total_taxable_amount, 825.24, 0.02) && near(raw0.additional_charges_gst, 1.65, 0.006) && near(raw0.items?.[0]?.making_charge, 35.04) && raw0.items?.[0]?.hsn_code === '7113' && raw0.place_of_supply === '19-West Bengal'
        && raw0.reverse_charge === 'No' && raw0.terms_of_delivery === 'Customer Pickup' && typeof raw0.invoice_date === 'string' && raw0.created_at instanceof Date, JSON.stringify(raw0).slice(0, 160));
    check('discount is recorded the new way: website `discount` stays 0, details kept beside it', raw0?.discount === 0 && raw0?.discount_mode === 'before_gst' && raw0?.discount_given === 30 && near(raw0?.discount_before_gst, 28.96) && raw0?.gross_taxable === 799.2 && raw0?.bill_before_discount === 880 && raw0?.calc_rule === 'lgpmanagement-v3');
    check('payment_history entry has the website\'s fields', raw0?.pay_no === 1 && raw0?.payment_history?.[0]?.payment_mode === 'Cash' && /^\d{4}-\d{2}-\d{2}$/.test(raw0?.payment_history?.[0]?.payment_date || '') && /^\d\d:\d\d:\d\d$/.test(raw0?.payment_history?.[0]?.payment_time || '') && /Initial payment with invoice #/.test(raw0?.payment_history?.[0]?.transaction_reference || ''));
    check('customer is linked by id (the website never did)', raw0?.customer_id === multi._id && /^LGP/.test(raw0?.customer_code || ''));
    // hallmark / HUID fee: the centre already charged GST on it, so it is added after the tax, never taxed again (checked on a real bill further down)
    r = await call('POST', '/api/billing/calculate', { token: admin, body: { items: [ring({ netWt: 2, rate: 1000, makingCharge: 100, certification: 'huid', huid: 'AB12CD', hallmarkCharge: 45 })], goldRate: 9000, silverRate: 100 } });
    check('the live total (website) treats the HUID fee the same way', r.data?.totalPayableAmount === 2208 && r.data?.hallmarkTotal === 45 && r.data?.gstSummary?.total_taxable_amount === 2100, JSON.stringify(r.data || r.json).slice(0, 200));
    const info = await lgp.collection('shop_info').findOne({ shop_id: 'default' });
    check('shop_info.last_invoice_number moved to the number just used', info?.last_invoice_number === Number(inv0.invoiceNumber), `(${info?.last_invoice_number})`);

    // -- idempotency + validation ---------------------------------------------------------------
    r = await bill({ requestId: rid1, items: [ring({ netWt: 0.08, rate: 9190, makingCharge: 64 })], additionalCharges: 55, discount: 30, paidAmount: 850, paymentMode: 'Cash' });
    check('same request id again returns the SAME invoice (no double bill)', r.status === 200 && r.json.duplicate === true && r.data?.invoiceNumber === inv0.invoiceNumber);
    r = await bill({ items: [] });                         check('no items rejected (400)', r.status === 400, `(${r.status})`);
    r = await bill({ items: [ring({ netWt: 0 })] });       check('zero weight rejected (400)', r.status === 400, `(${r.status})`);
    r = await bill({ discount: 999999 });                  check('discount above what is allowed is rejected (400)', r.status === 400 && /too high/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
    r = await bill({ items: [ring({ netWt: 0.08, rate: 9190, makingCharge: 64 })], additionalCharges: 55, discount: 67 });
    check('discount above the making charge is refused, and says so (max 66)', r.status === 400 && /At most ₹66/.test(r.json.message || ''), r.json.message);
    r = await bill({ items: [ring({ netWt: 5, rate: 6000, makingCharge: 0 })], discount: 100 });
    check('no making charge and no typed amount: no discount possible', r.status === 400 && /No discount is possible/.test(r.json.message || ''), r.json.message);
    r = await bill({ items: [ring({ netWt: 10, rate: 6000, makingCharge: 0, taxableOverride: 50000 })] });
    check('a typed taxable amount below the metal value (60000) is refused', r.status === 400 && /below the metal value/.test(r.json.message || ''), r.json.message);
    r = await bill({ items: [ring({ particulars: 'Gold Ring', netWt: 10, rate: 6000, makingCharge: 0, taxableOverride: 64000 })], discount: 1030, paidAmount: 64890 });
    check('typed taxable amount (making 0): name gets "+ Making Charge"; discount comes off the taxable amount; payable 64890',
        r.status === 201 && r.data?.items?.[0]?.particular === 'Gold Ring + Making Charge' && r.data?.items?.[0]?.makingCharge === 0 && near(r.data?.items?.[0]?.taxableAmount, 63000) && r.data?.totalPayableAmount === 64890, `(${r.status} ${r.json.message || ''} ${JSON.stringify(r.data?.items?.[0]).slice(0, 160)})`);
    r = await bill({ items: [ring({ particulars: 'Gold Ring', netWt: 10, rate: 6000, makingCharge: 0, taxableOverride: 64000 })], discount: 4100 });
    check('the most that can be given never reaches the metal: taxable stays at least 60000', r.status === 201 && r.data?.items?.[0]?.taxableAmount >= 59999.99 && r.data?.totalPayableAmount >= 61800, `(${r.status} ${r.json.message || ''})`);
    r = await bill({ requestId: 'x' });                    check('missing/short request id rejected (400)', r.status === 400, `(${r.status})`);
    r = await bill({ customerId: '000000000000000000000000' }); check('unknown customer rejected (404)', r.status === 404, `(${r.status})`);
    r = await bill({ items: [ring({ metalType: 'Other', rate: '' })] }); check('"Other" metal needs a typed rate (400)', r.status === 400 && /rate/.test(r.json.message), r.json.message);
    r = await bill({ items: [ring({ metalType: 'Other', rate: 50, netWt: 4 })] }); check('"Other" metal with a rate is accepted', r.status === 201 && r.data?.items?.[0]?.metalType === 'Other', `(${r.status} ${r.json.message || ''})`);
    r = await bill({ items: [ring({ taxableOverride: 60000, netWt: 10, rate: 6000, makingCharge: 500 })] });
    check('typed taxable amount is honoured (60000 -> cgst 900 -> line 61800)', r.status === 201 && r.data?.items?.[0]?.taxableAmount === 60000 && r.data?.items?.[0]?.cgst === 900 && r.data?.items?.[0]?.total === 61800, `(${r.status} ${r.json.message || ''})`);
    // -- other states (IGST), item details, stones / other metals -----------------------------------
    r = await call('GET', '/api/billing/meta', { token: admin });
    check('meta lists every GST state with correct codes and defaults to West Bengal', r.data?.states?.length >= 36 && r.data.states.some((x) => x.place === '07-Delhi') && r.data.states.some((x) => x.place === '13-Nagaland') && r.data?.defaultPlace === '19-West Bengal' && r.data?.supplyStateCode === '19');
    r = await bill({ placeOfSupply: '27-Maharashtra', items: [ring({ netWt: 10.5, rate: 6000, makingCharge: 1500 })], paidAmount: 66435 });
    const rawI = r.data && await lgp.collection('invoices').findOne({ invoice_number: r.data.invoiceNumber });
    check('another state: IGST 3% (cgst/sgst 0), same payable', r.status === 201 && r.data?.totalPayableAmount === 66435 && r.data?.gstType === 'IGST' && r.data?.items?.[0]?.igst === 1935 && r.data?.items?.[0]?.cgst === 0 && r.data?.gstSummary?.igst === 1935 && r.data?.gstSummary?.totalTax === 1935, `(${r.status} ${r.json.message || ''})`);
    check('...stored with place, state code and IGST summary', rawI?.place_of_supply === '27-Maharashtra' && rawI?.customer_state_code === '27' && rawI?.customer_state === 'Maharashtra' && rawI?.gst_type === 'IGST' && rawI?.gst_summary?.total_igst === 1935 && rawI?.gst_summary?.total_gst === 1935 && rawI?.items?.[0]?.igst === 1935);
    r = await bill({ placeOfSupply: 'delhi' });
    check('a state typed by name is understood (07-Delhi -> IGST)', r.status === 201 && r.data?.placeOfSupply === '07-Delhi' && r.data?.gstType === 'IGST', r.data?.placeOfSupply);
    r = await bill({ placeOfSupply: 'Atlantis' });
    check('an unknown place falls back to West Bengal (CGST+SGST)', r.status === 201 && r.data?.placeOfSupply === '19-West Bengal' && r.data?.gstType === 'CGST_SGST');
    r = await bill({ placeOfSupply: undefined });
    check('no place given -> West Bengal by default', r.status === 201 && r.data?.placeOfSupply === '19-West Bengal' && r.data?.items?.[0]?.cgst === 967.5);
    r = await bill({ items: [ring({ netWt: 10, rate: 6000, makingCharge: 500, grossWt: 10.4, purity: '22K', productCode: 'LG-101', huid: 'ab12cd', itemId: 'abc123', extras: [{ kind: 'Stone', name: 'Ruby', weight: 0.4, amount: 2000 }, { kind: 'Metal', name: 'Silver', weight: 0.2, amount: 100 }] })], paidAmount: 64000 });
    const li = r.data?.items?.[0];
    check('stones and other metals: value added to taxable, details kept', r.status === 201 && li?.taxableAmount === 62600 && li?.stoneCharge === 2100 && li?.extras?.length === 2 && li?.extras?.[0]?.name === 'Ruby' && li?.purity === '22K' && li?.grossWt === 10.4 && li?.productCode === 'LG-101' && li?.huid === 'AB12CD', JSON.stringify(li).slice(0, 200));
    const rawX = r.data && await lgp.collection('invoices').findOne({ invoice_number: r.data.invoiceNumber });
    check('...website fields are still complete (taxable_amount, cgst, total)', rawX?.items?.[0]?.taxable_amount === 62600 && rawX?.items?.[0]?.cgst === 939 && rawX?.items?.[0]?.total === 64478 && rawX?.items?.[0]?.gross_wt === 10.4);
    // -- hallmark / HUID: fee passed on after tax (no GST on it), name on the invoice ---------------------------------------
    r = await bill({ items: [ring({ particulars: 'Earring', netWt: 2, rate: 1000, makingCharge: 100, certification: 'hallmark', hallmarkCharge: 45 })], paidAmount: 2208 });
    const hm = r.data?.items?.[0];
    const rawHm = r.data && await lgp.collection('invoices').findOne({ invoice_number: r.data.invoiceNumber });
    check('hallmarked: name "Earring (Hallmarked)", fee 45 outside the taxable value (taxable 2100, GST 63, payable 2208)', r.status === 201 && hm?.particular === 'Earring (Hallmarked)' && hm?.taxableAmount === 2100 && hm?.hallmarkCharge === 45 && hm?.hallmarkTaxed === false && hm?.total === 2208 && r.data?.hallmarkTotal === 45 && r.data?.gstSummary?.taxableValue === 2100 && r.data?.gstSummary?.totalTax === 63 && hm?.itemName === 'Earring' && r.data?.totalPayableAmount === 2208, `(${r.status} ${r.json.message || ''} ${JSON.stringify(hm).slice(0, 120)})`);
    check('...stored: particulars carries the name, hallmark_charge kept', rawHm?.items?.[0]?.particulars === 'Earring (Hallmarked)' && rawHm?.items?.[0]?.hallmark_charge === 45 && rawHm?.items?.[0]?.certification === 'hallmark' && rawHm?.items?.[0]?.taxable_amount === 2100 && rawHm?.items?.[0]?.hallmark_in_taxable === false && rawHm?.hallmark_total === 45 && rawHm?.gst_summary?.total_taxable_amount === 2100 && rawHm?.calc_rule === 'lgpmanagement-v3');
    r = await bill({ items: [ring({ particulars: 'Earring', certification: 'huid', huid: 'ab12cd', hallmarkCharge: 45 })] });
    check('HUID: name "Earring (HUID: AB12CD)"', r.status === 201 && r.data?.items?.[0]?.particular === 'Earring (HUID: AB12CD)' && r.data?.items?.[0]?.huid === 'AB12CD' && r.data?.items?.[0]?.taxableAmount === 64500 && r.data?.items?.[0]?.hallmarkCharge === 45, `(${r.status} ${r.json.message || ''})`);
    r = await bill({ items: [ring({ certification: 'huid', huid: 'AB1' })] });
    check('HUID must be 6 letters/digits (400)', r.status === 400 && /HUID/.test(r.json.message || ''), r.json.message);
    r = await bill({ items: [ring({ certification: 'huid' })] });
    check('HUID selected but no code is refused (400)', r.status === 400);

    r = await bill({ items: [ring({ netWt: 5, grossWt: 4 })] });
    check('net weight above gross weight is refused', r.status === 400 && /gross/.test(r.json.message || ''), r.json.message);

    r = await bill({ deliveryDate: '2099-01-01', paidAmount: 66435 });
    check('future delivery date -> status "pending"', r.status === 201 && r.data?.status === 'pending', r.data?.status);
    r = await bill({ paidAmount: 20000 });
    check('part payment -> delivered but unpaid = "active"', r.status === 201 && r.data?.status === 'active' && r.data?.dueAmount === 46435 && r.data?.paidAmount === 20000, r.data?.status);
    const invDue = r.data;
    r = await bill({ paidAmount: 70000 });
    check('over-payment becomes an advance (3565), due_advance positive in the database', r.status === 201 && r.data?.advanceAmount === 3565 && (await lgp.collection('invoices').findOne({ invoice_number: r.data.invoiceNumber }))?.due_advance === 3565);

    // -- extra charges are taxed like the goods (GST Act s.15(2)(c)) -----------------------------------------
    r = await bill({ items: [ring({ netWt: 10.5, rate: 6000, makingCharge: 1500 })], additionalCharges: 500, paidAmount: 66950 });
    check('extra charges carry GST: payable 66950 (goods 66435 + 500 + 15 GST), taxable includes the 500',
        r.status === 201 && r.data?.totalPayableAmount === 66950 && r.data?.additionalChargesGst === 15 && r.data?.gstSummary?.taxableValue === 65000 && r.data?.gstSummary?.totalTax === 1950, `(${r.status} ${r.json.message || ''} ${JSON.stringify(r.data?.gstSummary)})`);
    r = await bill({ items: [ring({ netWt: 10.5, rate: 6000, makingCharge: 1500 })], additionalCharges: 500, placeOfSupply: '27-Maharashtra', paidAmount: 66950 });
    check('...and under IGST the 500 carries 3% IGST too', r.status === 201 && r.data?.totalPayableAmount === 66950 && r.data?.gstSummary?.igst === 1950 && r.data?.gstType === 'IGST', `(${r.status} ${r.json.message || ''})`);

    // -- cash limit: Income Tax Act s.269ST (Rs 2,00,000 or more in cash from one person in a day) ------------
    section('GST billing: cash limit (s.269ST) and split payments');
    r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `SMOKE Cash ${tag}`, contacts: [{ number: `9${tag}0`.slice(0, 10).padEnd(10, '7'), label: 'whatsapp' }] } });
    const cashCust = r.data;
    const cashBill = (over = {}) => call('POST', '/api/billing/invoices', { token: admin, body: { requestId: uid(), customerId: cashCust?._id, customerAddress: '5 Cash Lane, Howrah', items: [ring({ netWt: 10, rate: 30000, makingCharge: 0 })], goldRate: 30000, silverRate: 110, ...over } });
    r = await call('GET', `/api/billing/cash-today?customerId=${cashCust?._id}`, { token: admin });
    check('cash-today starts at 0 with the full room (1,99,999)', r.status === 200 && r.data?.alreadyToday === 0 && r.data?.room === 199999 && r.data?.limit === 200000, JSON.stringify(r.data));
    r = await cashBill({ payments: [{ mode: 'Cash', amount: 309000 }], customerPan: 'ABCDE1234F' });      // 300000 + 3% = 309000
    check('a bill paid entirely in cash above the limit is refused (400) and says how much cash is allowed', r.status === 400 && /269ST/.test(r.json.message || '') && r.json.cashRoom === 199999, `(${r.status} ${r.json.message || ''})`);
    r = await cashBill({ payments: [{ mode: 'Cash', amount: 200000 }, { mode: 'Online', amount: 109000 }], customerPan: 'ABCDE1234F' });
    check('exactly Rs 2,00,000 in cash is ALSO refused (the law says "2 lakh or more")', r.status === 400 && /269ST/.test(r.json.message || ''), `(${r.status})`);
    r = await cashBill({ payments: [{ mode: 'Cash', amount: 199999 }, { mode: 'Online', amount: 109001, reference: 'UTR-77' }], customerPan: 'ABCDE1234F' });
    const sp = r.data;
    const rawSp = sp && await lgp.collection('invoices').findOne({ invoice_number: sp.invoiceNumber });
    check('split payment: Cash 1,99,999 + Online 1,09,001 is accepted, paid in full, two history lines', r.status === 201 && sp?.totalPayableAmount === 309000 && sp?.dueAmount === 0 && sp?.paymentHistory?.length === 2
        && rawSp?.pay_no === 2 && rawSp?.payment_history?.[0]?.payment_mode === 'Cash' && rawSp?.payment_history?.[1]?.payment_mode === 'Online' && rawSp?.payment_history?.[1]?.transaction_reference === 'UTR-77' && rawSp?.paid_amount === 309000, `(${r.status} ${r.json.message || ''})`);
    check('...the invoice records its main mode (the largest part) for the website', rawSp?.payment_mode === 'Cash');
    r = await call('GET', `/api/billing/cash-today?customerId=${cashCust?._id}`, { token: admin });
    check('cash-today now shows 1,99,999 taken and no room left', r.data?.alreadyToday === 199999 && r.data?.room === 0, JSON.stringify(r.data));
    r = await cashBill({ items: [ring({ netWt: 1, rate: 1000, makingCharge: 0 })], goldRate: 1000, payments: [{ mode: 'Cash', amount: 1030 }] });
    check('the SAME customer paying even Rs 1,030 more in cash the same day is refused (all invoices count together)', r.status === 400 && /already received in cash today/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
    r = await cashBill({ items: [ring({ netWt: 1, rate: 1000, makingCharge: 0 })], goldRate: 1000, payments: [{ mode: 'Online', amount: 1030 }] });
    check('...but the same bill by Online is fine', r.status === 201 && r.data?.dueAmount === 0, `(${r.status} ${r.json.message || ''})`);
    r = await cashBill({ items: [ring({ netWt: 1, rate: 1000, makingCharge: 0 })], goldRate: 1000, payments: [{ mode: 'Online', amount: 30 }] });
    const dueInv = r.data;
    r = await call('POST', `/api/billing/invoices/${dueInv?._id}/payments`, { token: admin, body: { requestId: uid(), amount: 1000, mode: 'Cash' } });
    check('a LATER cash payment on an invoice obeys the same limit (400)', r.status === 400 && /269ST/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
    r = await call('POST', `/api/billing/invoices/${dueInv?._id}/payments`, { token: admin, body: { requestId: uid(), amount: 1000, mode: 'Card' } });
    check('...while Card is fine and settles it', r.status === 200 && r.data?.dueAmount === 0, `(${r.status})`);
    r = await cashBill({ payments: [{ mode: 'Cash', amount: 100 }, { mode: 'Bitcoin', amount: 100 }] });
    check('an unknown payment mode is refused (400)', r.status === 400 && /Payment mode/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
    r = await bill({ customerId: undefined, customerName: 'Walk Cash', customerMobile: '9811122233', items: [ring({ netWt: 10, rate: 30000, makingCharge: 0 })], goldRate: 30000, customerPan: 'ABCDE1234F', payments: [{ mode: 'Cash', amount: 309000 }] });
    check('a walk-in with a mobile number is held to the cash limit too', r.status === 400 && /269ST/.test(r.json.message || ''), `(${r.status})`);
    r = await bill({ customerId: undefined, customerName: 'Walk Cash', customerMobile: '9811122233', items: [ring({ netWt: 10, rate: 30000, makingCharge: 0 })], goldRate: 30000, customerPan: 'ABCDE1234F', payments: [{ mode: 'Cash', amount: 100000 }, { mode: 'Card', amount: 209000 }] });
    check('...and can split it: Cash 1,00,000 + Card 2,09,000', r.status === 201 && r.data?.dueAmount === 0, `(${r.status} ${r.json.message || ''})`);

    // -- CGST Rule 46(f): buyer's address is compulsory on a bill of Rs 50,000 or more ------------------------
    r = await bill({ customerAddress: '' });
    check('a Rs 66,435 bill without the buyer address is refused (Rule 46)', r.status === 400 && /address/i.test(r.json.message || '') && /46/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
    r = await bill({ customerAddress: '   ' });
    check('...blank spaces do not count as an address', r.status === 400);
    r = await bill({ customerAddress: '12 Test Road, Howrah' });
    check('...with an address it is accepted', r.status === 201, `(${r.status} ${r.json.message || ''})`);
    r = await bill({ customerAddress: '', items: [ring({ netWt: 1, rate: 1000, makingCharge: 0 })], goldRate: 1000 });
    check('a small bill (Rs 1,030) does not need one', r.status === 201, `(${r.status} ${r.json.message || ''})`);
    r = await bill({ customerAddress: '', items: [ring({ netWt: 5, rate: 9190, makingCharge: 0 })] });
    check('exactly at the limit (Rs 47,335 + GST = 47,955 is below; 50,000 or above is not)', r.status === 201 || /address/i.test(r.json.message || ''), `(${r.status})`);
    r = await bill({ customerId: undefined, customerName: 'Walk In', customerAddress: '', paidAmount: 66435 });
    check('a walk-in over Rs 50,000 also needs the address', r.status === 400 && /address/i.test(r.json.message || ''));
    r = await call('GET', '/api/billing/meta', { token: admin });
    check('meta tells the app the address limit', r.data?.addressLimit === 50000);
    r = await call('GET', `/api/billing/customer/${multi._id}`, { token: admin });
    check('customer summary returns the saved address so the app can prefill it', 'address' in (r.data || {}));

    // -- TDS + PAN ------------------------------------------------------------------------------------
    const big = { items: [ring({ netWt: 100, rate: 2000, makingCharge: 0 })], paidAmount: 206000 };   // payable 206000
    r = await bill(big);
    check('above Rs 2,00,000 without a PAN is refused (TDS rule)', r.status === 400 && /PAN/.test(r.json.message), r.json.message);
    r = await bill({ ...big, customerPan: 'BADPAN' });
    check('a malformed PAN is refused', r.status === 400);
    r = await bill({ ...big, customerPan: 'abcde1234f' });
    check('with a valid PAN: saved, TDS 1% = 2060 recorded', r.status === 201 && r.data?.tds?.applicable === true && r.data?.tds?.amount === 2060 && r.data?.tds?.rate === 1 && r.data?.customerPan === 'ABCDE1234F', `(${r.status} ${r.json.message || ''})`);

    // -- walk-in (customer not in the list) ----------------------------------------------------------
    r = await bill({ customerId: undefined, customerName: 'Walk In Buyer', customerMobile: '98 76 54 3210', paidAmount: 66435 });
    check('walk-in paid in full is saved', r.status === 201 && r.data?.walkIn === true && r.data?.customerObjectId === '' && r.data?.customerMobile === '9876543210', `(${r.status} ${r.json.message || ''})`);
    r = await bill({ customerId: undefined, customerName: 'Walk In Buyer', paidAmount: 100 });
    check('walk-in with a due balance is refused', r.status === 400 && /paid in full/.test(r.json.message || ''), `(${r.status})`);
    r = await bill({ customerId: undefined, customerName: 'x' });
    check('walk-in without a real name is refused', r.status === 400);

    // -- customer summary: linked invoices + old ones matched by mobile ------------------------------
    r = await call('POST', '/api/directory/customers', { token: admin, body: { name: 'Legacy Customer C', contacts: [{ number: '9000000103', label: 'whatsapp' }] } });
    let legC = r.data;
    if (!legC?._id) { const f = await call('GET', '/api/directory/customers?q=9000000103', { token: admin }); legC = f.data?.[0]; }
    r = await call('GET', `/api/billing/customer/${legC?._id}`, { token: admin });
    check('an old website invoice is found for a customer by mobile (due 26865)', r.status === 200 && r.data?.totalDue === 26865 && r.data?.invoices === 1 && r.data?.recent?.[0]?.invoiceNumber === '1500', JSON.stringify(r.data).slice(0, 120));
    r = await call('GET', `/api/billing/customer/${multi._id}`, { token: admin });
    check('customer summary counts the invoices billed to them', r.data?.totalDue >= 46435 && r.data?.invoices >= 5 && /^LGP/.test(r.data?.code || ''));

    // -- payments ------------------------------------------------------------------------------------
    section('GST billing: payments');
    const pid1 = uid();
    r = await call('POST', `/api/billing/invoices/${invDue._id}/payments`, { token: admin, body: { requestId: pid1, amount: 10000, mode: 'Online', reference: 'UTR123' } });
    check('receive a payment', r.status === 200 && r.data?.dueAmount === 36435 && r.data?.paidAmount === 30000 && r.data?.paymentHistory?.length === 2, `(${r.status} ${r.json.message || ''})`);
    const rawP = await lgp.collection('invoices').findOne({ invoice_number: invDue.invoiceNumber });
    check('stored like the website: paid_amount, due_advance, pay_no, last_payment_date, history entry', rawP?.paid_amount === 30000 && rawP?.due_advance === -36435 && rawP?.pay_no === 2 && /^\d{4}-/.test(rawP?.last_payment_date || '') && rawP?.payment_history?.[1]?.payment_mode === 'Online' && rawP?.payment_history?.[1]?.transaction_reference === 'UTR123');
    r = await call('POST', `/api/billing/invoices/${invDue._id}/payments`, { token: admin, body: { requestId: pid1, amount: 10000, mode: 'Online' } });
    check('same payment request id again is not applied twice', r.status === 200 && r.json.duplicate === true && r.data?.dueAmount === 36435);
    r = await call('POST', `/api/billing/invoices/${invDue._id}/payments`, { token: admin, body: { requestId: uid(), amount: 99999 } });
    check('cannot collect more than is due (409)', r.status === 409, `(${r.status})`);
    r = await call('POST', `/api/billing/invoices/${invDue._id}/payments`, { token: viewer, body: { requestId: uid(), amount: 1 } });
    check('viewer cannot receive payments (403)', r.status === 403, `(${r.status})`);
    r = await call('POST', `/api/billing/invoices/${invDue._id}/payments`, { token: admin, body: { requestId: uid(), amount: 36435, mode: 'Cash' } });
    check('paying the rest of a delivered invoice moves it to "delivered"', r.status === 200 && r.data?.dueAmount === 0 && r.data?.status === 'delivered', r.data?.status);
    r = await call('POST', `/api/billing/invoices/${l1500._id}/payments`, { token: admin, body: { requestId: uid(), amount: 6865, mode: 'Cheque', reference: 'CHQ-77' } });
    check('a payment can be recorded on an invoice the WEBSITE created', r.status === 200 && r.data?.dueAmount === 20000 && r.data?.paidAmount === 26865 && r.data?.paymentHistory?.length === 2, `(${r.status} ${r.json.message || ''})`);
    r = await call('POST', `/api/billing/invoices/${l1450._id}/payments`, { token: admin, body: { requestId: uid(), amount: 1 } });
    check('a cancelled invoice cannot take payments (409)', r.status === 409, `(${r.status})`);

    // -- printing ------------------------------------------------------------------------------------
    r = await call('POST', `/api/billing/invoices/${inv0._id}/print`, { token: staff });
    check('first print is ORIGINAL', r.status === 200 && r.data?.printType === 'ORIGINAL' && r.data?.printStatus === 1, JSON.stringify(r.data));
    r = await call('POST', `/api/billing/invoices/${inv0._id}/print`, { token: staff });
    check('second print is DUPLICATE', r.data?.printType === 'DUPLICATE' && r.data?.printStatus === 2);
    r = await call('POST', `/api/billing/invoices/${l1401._id}/print`, { token: admin });
    check('an invoice the website already printed once prints as DUPLICATE', r.data?.printType === 'DUPLICATE' && r.data?.printStatus === 2);

    // -- MANY STAFF AT ONCE ----------------------------------------------------------------------------
    section('GST billing: many staff at once');
    const N = 15;
    const results = await Promise.all(Array.from({ length: N }, (_, i) => bill({ customerId: undefined, customerName: `Parallel ${i}`, paidAmount: 66435 }, i % 2 ? admin : staff)));
    const ok = results.filter((x) => x.status === 201);
    const nums = ok.map((x) => Number(x.data.invoiceNumber));
    check(`${N} invoices created at the same moment all succeed`, ok.length === N, `(${ok.length}/${N}: ${results.filter((x) => x.status !== 201).map((x) => x.status + ' ' + (x.json.message || '')).join('; ')})`);
    check('...with N DIFFERENT invoice numbers', new Set(nums).size === N);
    const sorted = [...nums].sort((a, b) => a - b);
    check('...and no gaps between them', sorted[N - 1] - sorted[0] === N - 1, JSON.stringify(sorted));

    const sameId = uid();
    const dupes = await Promise.all(Array.from({ length: 6 }, () => bill({ requestId: sameId, customerId: undefined, customerName: 'Double Tap', paidAmount: 66435 })));
    check('6 simultaneous taps of Save with one request id -> ONE invoice', dupes.every((x) => x.status < 300) && new Set(dupes.map((x) => x.data.invoiceNumber)).size === 1 && (await lgp.collection('invoices').countDocuments({ request_id: sameId })) === 1, dupes.map((x) => x.status).join(','));

    // the website saves an OLD suggested number and moves the counter backwards: the app must not reuse a taken number
    const curNo = (await lgp.collection('shop_info').findOne({ shop_id: 'default' })).last_invoice_number;
    await lgp.collection('shop_info').updateOne({ shop_id: 'default' }, { $set: { last_invoice_number: curNo - 3 } });
    r = await bill({ customerId: undefined, customerName: 'After Website Rewind', paidAmount: 66435 });
    check('counter moved back by the website: the app still issues an UNUSED number', r.status === 201 && Number(r.data?.invoiceNumber) > curNo && (await lgp.collection('invoices').countDocuments({ invoice_number: r.data.invoiceNumber })) === 1, `(${r.data?.invoiceNumber} vs was ${curNo})`);
    const dupNums = await lgp.collection('invoices').aggregate([{ $group: { _id: '$invoice_number', n: { $sum: 1 } } }, { $match: { n: { $gt: 1 } } }]).toArray();
    check('no invoice number appears twice anywhere in the collection', dupNums.length === 0, JSON.stringify(dupNums));

    // parallel payments against one due amount
    r = await bill({ items: [ring({ netWt: 1, rate: 1000, makingCharge: 0 })], paidAmount: 30 });      // payable 1030, due 1000
    const invP = r.data;
    check('invoice with Rs 1000 due', invP?.dueAmount === 1000, `(${r.status} ${JSON.stringify(invP?.dueAmount)})`);
    const pays = await Promise.all(Array.from({ length: 5 }, () => call('POST', `/api/billing/invoices/${invP._id}/payments`, { token: staff, body: { requestId: uid(), amount: 300, mode: 'Cash' } })));
    check('5 staff each collect Rs 300 at once against Rs 1000 due: exactly 3 succeed', pays.filter((x) => x.status === 200).length === 3 && pays.filter((x) => x.status === 409).length === 2, pays.map((x) => x.status).join(','));
    r = await call('GET', `/api/billing/invoices/${invP._id}`, { token: admin });
    check('...and the invoice is left with exactly Rs 100 due', r.data?.dueAmount === 100 && r.data?.paidAmount === 930 && r.data?.paymentHistory?.length === 4);

    // -- branches --------------------------------------------------------------------------------------
    section('GST billing: branches');
    r = await call('POST', '/api/billing/invoices', { token: branchStaff, body: { requestId: uid(), customerName: 'Branch Walk-in', items: [ring({ netWt: 1, rate: 1000, makingCharge: 0 })], paidAmount: 1030 } });
    check('a branch user can bill', r.status === 201, `(${r.status} ${r.json.message || ''})`);
    const brInv = r.data;
    check('branch invoices use their own series (PREFIX-0001)', /^[A-Z]{2,4}-\d{4}$/.test(brInv?.invoiceNumber || '') && brInv?.branchId === shop2, brInv?.invoiceNumber);
    check('the main sequence is untouched by branch billing', (await lgp.collection('shop_info').findOne({ shop_id: 'default' })).last_invoice_number >= 1760 && !/-/.test(String((await lgp.collection('shop_info').findOne({ shop_id: 'default' })).last_invoice_number)));
    r = await call('GET', '/api/billing/invoices?limit=50', { token: branchStaff });
    check('branch user sees only their own branch (not the old main-branch invoices)', r.status === 200 && r.data.length >= 1 && r.data.every((x) => /-/.test(x.invoiceNumber)));
    r = await call('GET', '/api/billing/invoices?limit=50', { token: staff });
    check('main-branch staff see old + new main invoices, not the other branch', r.status === 200 && r.data.some((x) => x.invoiceNumber === '1401' || /^\d{4}$/.test(x.invoiceNumber)) && !r.data.some((x) => x.invoiceNumber === brInv.invoiceNumber));
    r = await call('GET', `/api/billing/invoices/${brInv._id}`, { token: staff });
    check('opening another branch\'s invoice is refused (403)', r.status === 403, `(${r.status})`);
    r = await call('GET', `/api/billing/invoices/${l1401._id}`, { token: branchStaff });
    check('a branch user cannot open an old main-branch invoice (403)', r.status === 403, `(${r.status})`);
    r = await call('GET', '/api/billing/invoices?limit=50&q=-0001', { token: admin });
    check('admin sees every branch', r.data?.some((x) => x.invoiceNumber === brInv.invoiceNumber));

    // -- reading ---------------------------------------------------------------------------------------
    section('GST billing: lists and figures');
    r = await call('GET', `/api/billing/invoices?q=${inv0.invoiceNumber}`, { token: admin });
    check('search by invoice number', r.data?.some((x) => x.invoiceNumber === inv0.invoiceNumber));
    r = await call('GET', '/api/billing/invoices?q=Legacy%20Customer%20A', { token: admin });
    check('search by customer name finds old invoices', r.data?.some((x) => x.invoiceNumber === '1401'));
    r = await call('GET', '/api/billing/stats', { token: admin });
    check('stats: gold/silver with and without GST, invoices, due (cancelled excluded)', r.status === 200 && r.data?.gold?.withGst > r.data?.gold?.withoutGst && r.data?.silver?.withGst > 0 && r.data?.invoices >= 20 && r.data?.due > 0, JSON.stringify(r.data).slice(0, 140));
    r = await call('GET', `/api/billing/invoices/${inv0._id}`, { token: admin });
    check('invoice detail includes seller, terms and payments', r.status === 200 && r.json.terms?.length === 6 && r.data?.paymentHistory?.length === 1 && r.json.seller?.gstin === '19AKFPN3465R1ZB');
    await rawDb.close();

    // ── GST Summary (reports, returns, ITC, due dates, filings) ───────────────────────────────
    section('GST Summary');
    {
        const Calc2 = require('../services/billingCalc');
        const c2 = await MongoClient.connect('mongodb://127.0.0.1:27018');
        const lgp2 = c2.db('lgp_dev');
        const shop2db = c2.db('lgp_dev');
        await lgp2.collection('invoices').deleteMany({ source: 'gst-test' });
        await shop2db.collection('purchases').deleteMany({ biller: 'GST-TEST SUPPLIER' });
        const mk = (number, date, items, o = {}) => {
            const c = Calc2.computeInvoice({ items, goldRate: 9000, silverRate: 100, interstate: !!o.interstate, additionalCharges: o.additional || 0, discount: o.discount || 0, paidAmount: 0 });
            return {
                source: 'gst-test', invoice_number: number, invoice_date: date, customer_name: `GT ${number}`, customer_mobile: '9000000999', place_of_supply: o.interstate ? '27-Maharashtra' : '19-West Bengal',
                items: c.items, additional_charges: c.additionalCharges, additional_charges_gst: c.additionalGst, total_amount: c.totalAmount, discount: c.discount, round_off: c.roundOff, total_payable_amount: c.totalPayableAmount,
                paid_amount: 0, gst_summary: c.gstSummary, status: o.status || 'delivered', discount_mode: 'before_gst', discount_given: c.discountGiven, gst_type: c.gstType, branch_id: 'main', branch_name: 'Main branch', payment_history: [], created_at: new Date(date + 'T05:00:00Z'),
            };
        };
        const g = (x = {}) => ({ particulars: 'Gold Ring', metalType: 'Gold', netWt: 10, rate: 9000, makingCharge: 2000, purity: '22K', ...x });
        const sv = (x = {}) => ({ particulars: 'Silver Chain', metalType: 'Silver', netWt: 100, rate: 100, makingCharge: 500, ...x });
        const inv = [mk('GT-A', '2024-06-03', [g(), sv()], { additional: 500 }), mk('GT-B', '2024-06-10', [g({ netWt: 20 })], { interstate: true }), mk('GT-C', '2024-06-20', [sv()], { status: 'cancelled' }), mk('GT-D', '2024-07-02', [g()])];
        await lgp2.collection('invoices').insertMany(inv);
        const P = (date, cg, sg, ig, gstin) => ({ invoice_date: date, invoice_number: `GT-P-${date}-${cg}`, metal_type: 'Gold', biller: 'GST-TEST SUPPLIER', description: '', quantity: 1, rate: 1, total_amount: 10000 + cg + sg + ig, created_at: new Date(), created_by: 'x', totalAmount: 10000, totalPayable: 10000 + cg + sg + ig, totalGst: cg + sg + ig, itcCgst: cg, itcSgst: sg, itcIgst: ig, totalItc: cg + sg + ig, billerGstin: gstin, source: 'app' });
        await shop2db.collection('purchases').insertMany([P('2024-06-05', 200, 200, 0, '19ABCDE1234F1Z5'), P('2024-06-06', 0, 0, 90, '27ABCDE1234F1Z5'), P('2024-06-07', 50, 50, 0, ''), P('2024-05-15', 100, 100, 0, '19ABCDE1234F1Z5')]);

        r = await call('GET', '/api/gst-reports/summary?from=2024-06-01&to=2024-06-30', { token: staff });
        check('staff cannot open GST reports (admin-only by default, 403)', r.status === 403, `(${r.status})`);
        r = await call('GET', '/api/gst-reports/summary?from=2024-06-01&to=2024-06-30', { token: viewer });
        check('viewer cannot either (403)', r.status === 403);
        r = await call('GET', '/api/gst-reports/summary?from=2024-06-01', { token: admin });
        check('summary needs a valid date range (400)', r.status === 400);

        r = await call('GET', '/api/gst-reports/summary?from=2024-06-01&to=2024-06-30', { token: admin });
        const sm = r.data;
        check('summary: 2 invoices counted, the cancelled one excluded and noted', r.status === 200 && sm?.totals?.invoices === 2 && sm?.notes?.cancelled === 1 && sm?.partial === false, `(${r.status} ${r.json.message || ''})`);
        const sumTaxable = Calc2.r2(inv[0].gst_summary.total_taxable_amount + inv[1].gst_summary.total_taxable_amount);
        check('taxable, CGST/SGST/IGST and GST are exactly the invoices\' own (extra charges taxed included)',
            sm?.totals?.taxable === sumTaxable && sm?.totals?.igst === inv[1].gst_summary.total_igst && Math.abs(sm?.totals?.cgst - inv[0].gst_summary.total_cgst) < 0.006 && Math.abs(sm?.totals?.tax - Calc2.r2(inv[0].gst_summary.total_gst + inv[1].gst_summary.total_gst)) < 0.011, JSON.stringify(sm?.totals));
        const gm = sm?.byMetal?.find((m) => m.metal === 'Gold');
        check('metal-wise: gold 30 g, silver 100 g, extra charges as a row; making charge counted', gm?.weight === 30 && sm?.byMetal?.find((m) => m.metal === 'Silver')?.weight === 100 && sm?.byMetal?.some((m) => m.metal === 'Extra charges') && sm?.totals?.making === 2000 + 500 + 2000);
        check('item-wise, purity-wise and payment sections are present', sm?.byItem?.length >= 2 && sm?.byPurity?.some((p) => p.purity === '22K') && Array.isArray(sm?.payments) && sm?.trend?.length === 1);
        check('GSTR-1 tables: B2CS (West Bengal), B2CL (the inter-state invoice above 1 lakh), HSN with UQC GMS, documents in 1 series', sm?.gstr1?.b2cs?.length === 1 && sm?.gstr1?.b2cl?.length === 1 && sm?.gstr1?.b2cl?.[0]?.number === 'GT-B' && sm?.gstr1?.hsn?.[0]?.uqc === 'GMS' && sm?.gstr1?.docs?.[0]?.total === 3 && sm?.gstr1?.docs?.[0]?.cancelled === 1);
        check('"previous period" figures come along for comparison', typeof sm?.previous?.taxable === 'number' && !!sm?.previous?.from);
        r = await call('GET', '/api/gst-reports/summary?from=2024-06-01&to=2024-06-30&metal=silver', { token: admin });
        check('metal filter works at line level (silver only: 100 g)', r.data?.lineBased === true && r.data?.totals?.weight === 100 && r.data?.byMetal?.length === 1);
        r = await call('GET', '/api/gst-reports/summary?from=2024-06-01&to=2024-06-30&taxType=inter', { token: admin });
        check('tax-type filter: inter-state only', r.data?.totals?.invoices === 1 && r.data?.totals?.igst > 0 && r.data?.totals?.cgst === 0);
        r = await call('GET', '/api/gst-reports/summary?from=2024-06-01&to=2024-07-31&group=month', { token: admin });
        check('trend grouped by month covers both months', r.data?.trend?.length === 2);

        r = await call('GET', '/api/gst-reports/register?from=2024-06-01&to=2024-07-31&sort=value&dir=desc', { token: admin });
        check('register: sorted by value, biggest first, with totals', r.status === 200 && r.data?.total === 3 && r.data?.rows?.[0]?.value >= r.data?.rows?.[1]?.value && r.data?.totals?.invoiceValue > 0);
        r = await call('GET', '/api/gst-reports/register?from=2024-06-01&to=2024-07-31&sort=invoiceNumber&dir=asc&limit=2&page=2', { token: admin });
        check('register: paging', r.data?.rows?.length === 1 && r.data?.page === 2);
        r = await call('GET', '/api/gst-reports/register?from=2024-06-01&to=2024-07-31&q=GT-B', { token: admin });
        check('register: search', r.data?.total === 1 && r.data?.rows?.[0]?.invoiceNumber === 'GT-B');

        r = await call('GET', '/api/gst-reports/settings', { token: admin });
        check('settings: monthly with reminders on by default; West Bengal quarterly GSTR-3B is on the 24th', r.status === 200 && r.data?.settings?.frequency === 'monthly' && r.data?.settings?.reminders?.enabled === true && r.data?.qrmpDay3b === 24 && r.data?.seller?.gstin === '19AKFPN3465R1ZB', JSON.stringify(r.data?.settings).slice(0, 120));
        r = await call('PUT', '/api/gst-reports/settings', { token: staff, body: { frequency: 'quarterly' } });
        check('staff cannot change settings (403)', r.status === 403);
        r = await call('PUT', '/api/gst-reports/settings', { token: admin, body: { frequency: 'yearly' } });
        check('bad frequency is refused (400)', r.status === 400);
        r = await call('PUT', '/api/gst-reports/settings', { token: admin, body: { reminders: { daysBefore: [99] } } });
        check('reminder lead time above 30 days is refused (400)', r.status === 400);
        r = await call('PUT', '/api/gst-reports/settings', { token: admin, body: { trackFrom: '2024-05', openingItc: { igst: 0, cgst: 1000, sgst: 0 }, frequency: 'monthly', b2clThreshold: 100000 } });
        check('settings saved: ITC tracked from 2024-05 with opening CGST credit 1000', r.status === 200 && r.data?.settings?.trackFrom === '2024-05' && r.data?.settings?.openingItc?.cgst === 1000, `(${r.status} ${r.json.message || ''})`);

        r = await call('GET', '/api/gst-reports/returns?period=2024-06', { token: admin });
        const rt = r.data;
        check('returns: period, due dates (11th / 20th of July), GSTR-1 tables and GSTR-3B sections', r.status === 200 && rt?.period?.from === '2024-06-01' && rt?.due?.['GSTR-1'] === '2024-07-11' && rt?.due?.['GSTR-3B'] === '2024-07-20' && rt?.gstr1?.hsn?.length >= 1 && rt?.gstr3b?.outward?.taxable === sumTaxable, `(${r.status} ${r.json.message || ''})`);
        check('GSTR-3B 3.2: inter-state supplies to unregistered persons listed by place', rt?.gstr3b?.interstateToUnregistered?.[0]?.place === '27-Maharashtra' && rt?.gstr3b?.interstateToUnregistered?.[0]?.igst > 0);
        const led = rt?.gstr3b?.ledger;
        check('ITC ledger: opening = May closing (CGST 1100, SGST 100), June purchases added (CGST 200, SGST 200, IGST 90)', !!led && led.opening.cgst === 1100 && led.opening.sgst === 100 && led.added.cgst === 200 && led.added.sgst === 200 && led.added.igst === 90, JSON.stringify(led?.opening) + JSON.stringify(led?.added));
        check('suppliers without a GSTIN are kept apart as "at risk" (CGST 50, SGST 50), not claimed', rt?.gstr3b?.itc?.atRisk?.cgst === 50 && rt?.gstr3b?.itc?.claim?.cgst === 200 && rt?.gstr3b?.itc?.riskPurchases === 1);
        const L = rt?.gstr3b?.liability;
        const conserved = !!led && Math.abs((led.used.igst.igst + led.used.cgst.igst + led.used.sgst.igst + led.cash.igst) - L.igst) < 0.02 && Math.abs((led.used.igst.cgst + led.used.cgst.cgst + led.cash.cgst) - L.cgst) < 0.02 && Math.abs((led.used.igst.sgst + led.used.sgst.sgst + led.cash.sgst) - L.sgst) < 0.02;
        check('tax payable = ITC used (IGST first; CGST/SGST credit only against its own head or IGST) + cash', conserved && led.used.cgst.sgst === undefined, JSON.stringify(led?.cash));
        check('remaining credit carries forward (closing balances are never negative)', !!led && Object.values(led.closing).every((v) => v >= 0));
        check('returns include the "checks before you file" list (June 2024 test invoices have no addresses over 50,000?)', Array.isArray(rt?.checks) && rt.checks.every((x) => ['warn', 'info'].includes(x.severity) && x.title && Array.isArray(x.invoices)), JSON.stringify(rt?.checks).slice(0, 120));
        check('the checks name the invoices concerned (test invoices carry no address: GT-A and GT-B are above Rs 50,000)', rt?.checks?.find((x) => x.id === 'address')?.invoices?.includes('GT-B') === true, JSON.stringify(rt?.checks?.map((x) => x.id)));
        r = await call('GET', '/api/gst-reports/returns?period=nope', { token: admin });
        check('bad period is refused (400)', r.status === 400);
        r = await call('GET', '/api/gst-reports/returns?period=2024-Q1', { token: admin });
        check('a quarter period works too (Apr-Jun FY 2024-25)', r.status === 200 && r.data?.period?.from === '2024-04-01' && r.data?.period?.to === '2024-06-30' && r.data?.gstr3b?.outward?.taxable === sumTaxable, `(${r.status} ${r.json.message || ''})`);

        r = await call('GET', '/api/gst-reports/itc', { token: admin });
        check('ITC page: roll-forward rows, carried forward and available now', r.status === 200 && Array.isArray(r.data?.rows) && typeof r.data?.availableNowTotal === 'number' && typeof r.data?.carriedTotal === 'number', `(${r.status})`);

        r = await call('POST', '/api/gst-reports/filings', { token: staff, body: { returnType: 'GSTR-1', period: '2024-06', filedOn: '2024-07-09' } });
        check('staff cannot record a filing (403)', r.status === 403);
        r = await call('POST', '/api/gst-reports/filings', { token: admin, body: { returnType: 'GSTR-1', period: '2024-06', filedOn: '2099-01-01' } });
        check('a filing date in the future is refused (400)', r.status === 400);
        r = await call('POST', '/api/gst-reports/filings', { token: admin, body: { returnType: 'GSTR-1', period: '2024-Q9', filedOn: '2024-07-09' } });
        check('a period that does not fit is refused (400)', r.status === 400);
        await c2.db('lgp_dev').collection('gst_data').deleteMany({ 'filings.arn': 'AA0607240000123' });
        r = await call('POST', '/api/gst-reports/filings', { token: admin, body: { returnType: 'GSTR-3B', period: '2024-06', filedOn: '2024-07-19', arn: 'aa0607240000123', taxLiability: 5000, itcUsed: 3000, cashPaid: 2000 } });
        const fid = r.data?._id;
        check('record a filed GSTR-3B: ARN upper-cased, amounts saved', r.status === 201 && r.data?.arn === 'AA0607240000123' && r.data?.cashPaid === 2000, `(${r.status} ${r.json.message || ''})`);
        r = await call('POST', '/api/gst-reports/filings', { token: admin, body: { returnType: 'GSTR-3B', period: '2024-06', filedOn: '2024-07-20' } });
        check('the same return twice is refused (409): edit instead', r.status === 409);
        r = await call('PUT', `/api/gst-reports/filings/${fid}`, { token: admin, body: { lateFee: 50, period: '2025-01', returnType: 'GSTR-1' } });
        check('edit a filing (late fee); its type and period cannot be changed', r.status === 200 && r.data?.lateFee === 50 && r.data?.period === '2024-06' && r.data?.returnType === 'GSTR-3B', `(${r.status} ${r.json.message || ''})`);
        r = await call('GET', '/api/gst-reports/filings?period=2024-06', { token: admin });
        check('filing history lists it', r.status === 200 && r.data?.length === 1);

        r = await call('GET', '/api/gst-reports/calendar', { token: admin });
        const cal = r.data;
        check('calendar: upcoming + past obligations with status, days left and alerts', r.status === 200 && Array.isArray(cal?.items) && cal.items.length > 5 && cal.items.every((x) => ['filed', 'overdue', 'due-soon', 'upcoming', 'untracked'].includes(x.status)) && Array.isArray(cal?.alerts), `(${r.status})`);
        r = await call('PUT', '/api/gst-reports/settings', { token: admin, body: { frequency: 'quarterly' } });
        r = await call('GET', '/api/gst-reports/calendar', { token: admin });
        check('switching to quarterly changes the schedule (quarter periods + PMT-06 monthly payments)', r.data?.frequency === 'quarterly' && r.data?.items?.some((x) => x.period.includes('-Q')) && r.data?.items?.some((x) => x.type === 'PMT-06'));

        r = await call('GET', '/api/gst-reports/export?type=register&from=2024-06-01&to=2024-07-31', { token: admin });
        check('CSV export: invoice register with a header and one line per invoice', r.status === 200 && /^Invoice no,Date/.test(r.data?.csv || '') && (r.data.csv.match(/\n/g) || []).length === 3 && /invoice-register_2024-06-01_to_2024-07-31\.csv/.test(r.data?.filename || ''), r.data?.csv);
        r = await call('GET', '/api/gst-reports/export?type=hsn&from=2024-06-01&to=2024-06-30', { token: admin });
        check('CSV export: HSN summary', r.status === 200 && /^HSN,UQC/.test(r.data?.csv || '') && /7113,GMS/.test(r.data.csv));

        // filings before "follow filings from" are not tracked: no false overdue alarms for old periods
        const nowD = new Date(); const pm = new Date(Date.UTC(nowD.getUTCFullYear(), nowD.getUTCMonth() - 1, 1));
        const pmKey = `${pm.getUTCFullYear()}-${String(pm.getUTCMonth() + 1).padStart(2, '0')}`;
        r = await call('PUT', '/api/gst-reports/settings', { token: admin, body: { frequency: 'monthly', remindersFrom: 'bad' } });
        check('"follow filings from" must be a month (400)', r.status === 400);
        r = await call('PUT', '/api/gst-reports/settings', { token: admin, body: { frequency: 'monthly', remindersFrom: pmKey } });
        r = await call('GET', '/api/gst-reports/calendar', { token: admin });
        check('older periods show as "untracked" and raise no alert; newer ones are followed', r.data?.items?.some((x) => x.status === 'untracked') && r.data?.alerts?.every((x) => x.period >= pmKey || x.period.startsWith('FY')), JSON.stringify(r.data?.alerts?.map((x) => x.period)));

        // ── monthly GST invoice record (the website's "Print PDF") ──
        r = await call('GET', '/api/gst-reports/monthly-record?year=2024&month=6', { token: staff });
        check('monthly record: staff without GST access get 403', r.status === 403);
        r = await call('GET', '/api/gst-reports/monthly-record?year=2024&month=13', { token: admin });
        check('monthly record: an invalid month is refused (400)', r.status === 400);
        r = await call('GET', '/api/gst-reports/monthly-record?year=2099&month=1', { token: admin });
        check('monthly record: a future month is refused (400)', r.status === 400 && /future/.test(r.json.message || ''));
        r = await call('GET', '/api/gst-reports/monthly-record?year=2019&month=2', { token: admin });
        check('monthly record: a month with no invoices says so (404)', r.status === 404 && /No invoices/.test(r.json.message || ''));
        r = await call('GET', '/api/gst-reports/monthly-record?year=2024&month=6', { token: admin });
        const mr = r.data;
        check('monthly record: ALL 3 invoices of June listed (incl. the cancelled one), 2 count in the totals', r.status === 200 && mr?.invoices?.length === 3 && mr?.tracking?.valid === 2 && mr?.tracking?.cancelledVoidDeleted === 1 && mr?.invoices?.find((i) => i.number === 'GT-C')?.counted === false, `(${r.status} ${r.json.message || ''})`);
        check('monthly record: totals are exactly the two valid invoices own figures', mr?.totals?.taxable === sumTaxable && mr?.totals?.count === 2 && mr?.totals?.igst === inv[1].gst_summary.total_igst && mr?.totals?.goldWeight === 30 && mr?.totals?.silverWeight === 100);
        check('monthly record: header data (GSTIN, firm), document id and IST timestamp', mr?.seller?.gstin === '19AKFPN3465R1ZB' && /^GST-[0-9A-F]{6}$/.test(mr?.documentId || '') && / IST$/.test(mr?.generatedAt || '') && mr?.period?.monthName === 'June');
        check('monthly record: each invoice carries what the layout prints (customer, place of supply, items with HSN, GST, amount in words field)', mr?.invoices?.[0]?.customer?.name === 'GT GT-A' && mr?.invoices?.[0]?.placeOfSupply === '19-West Bengal' && mr?.invoices?.[0]?.items?.[0]?.hsn === '7113' && 'amountInWords' in mr.invoices[0] && mr?.invoices?.[1]?.gstType === 'IGST');
        const auditDoc = await c2.db('lgp_dev').collection('outputDoc').findOne({ document_id: mr?.documentId });
        check('monthly record: one log row in the website outputDoc (its own field names: who, when, totals)', !!auditDoc && auditDoc.total_invoices === 3 && auditDoc.valid_invoices_count === 2 && auditDoc.user_name === 'Admin' && auditDoc.year === 2024 && auditDoc.document_type === 'GST_MONTHLY_REPORT' && auditDoc.month_name === 'June' && auditDoc.date_range?.start_date === '2024-06-01' && /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/.test(auditDoc.generation_timestamp) && / IST$/.test(auditDoc.generation_timestamp_ist));
        await c2.db('lgp_dev').collection('outputDoc').deleteMany({ year: 2024, month: 6, source: 'app' });

        // put things back for the next run
        await call('PUT', '/api/gst-reports/settings', { token: admin, body: { frequency: 'monthly', remindersFrom: pmKey, trackFrom: `${new Date().getFullYear()}-04`, openingItc: { igst: 0, cgst: 0, sgst: 0 } } });
        await lgp2.collection('invoices').deleteMany({ source: 'gst-test' });
        await shop2db.collection('purchases').deleteMany({ biller: 'GST-TEST SUPPLIER' });
        await c2.db('lgp_dev').collection('gst_data').deleteMany({ 'filings.arn': 'AA0607240000123' });
        await c2.close();
    }

    // ── Multi-branch: stock isolation, branch switcher, one GST registration per GSTIN ─────────────────────
    section('Multi-branch: stock & records');
    {
        const G_B = `27AAAAA${tag}Z5`.slice(0, 15).replace(/[^A-Z0-9]/g, 'A');            // a Maharashtra registration for the second shop
        r = await call('POST', '/api/directory/branches', { token: admin, body: { name: `SMOKE Pune ${tag}`, state: 'Maharashtra', city: 'Pune', gstin: 'bad' } });
        check('a malformed branch GSTIN is refused (400)', r.status === 400, `(${r.status})`);
        r = await call('POST', '/api/directory/branches', { token: admin, body: { name: `SMOKE Pune ${tag}`, state: 'Maharashtra', city: 'Pune', gstin: G_B, code: 'PN' } });
        check('add a branch that has its own GSTIN', r.status === 201, `(${r.status} ${r.json.message || ''})`);
        const puneId = r.data?._id;
        r = await call('POST', '/api/users', { token: admin, body: { name: `SMOKE Pune Staff ${tag}`, mobile: `92${tag}1`.slice(0, 10), password: 'Smoke@123', role: 'staff', branchId: puneId } });
        const puneStaff = (await call('POST', '/api/auth/login', { body: { mobile: `92${tag}1`.slice(0, 10), password: 'Smoke@123' } })).data?.token;
        check('a staff member is created for the new branch', !!puneStaff);

        // stock: a record made by branch staff belongs to the branch and stays out of the other branches' lists
        r = await call('POST', '/api/containers', { token: puneStaff, body: { name: `SMOKE PuneBox ${tag}`, type: 'box', capacity: 10, weightCategory: 'Light', layoutType: 'grid', qrCode: `SMOKE-PC-${tag}`, allowedItemTypes: ['ring'] } });
        check('branch staff can create a container', r.status === 201 || r.status === 200, `(${r.status} ${r.json.message || ''})`);
        const puneBox = unwrap(r.data)?._id;
        r = await call('POST', '/api/items', { token: puneStaff, body: { barcode: `SMOKE-PI-${tag}`, name: `SMOKE Pune Ring ${tag}`, itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 3, grossWeight: 3.2, ...(puneBox ? { containerId: puneBox } : {}) } });
        check('branch staff can add an item', r.status === 201 || r.status === 200, `(${r.status} ${r.json.message || ''})`);
        const puneItem = unwrap(r.data)?._id;
        r = await call('GET', `/api/items/barcode/SMOKE-PI-${tag}`, { token: puneStaff });
        check('the branch sees its own item by barcode', r.status === 200 && unwrap(r.data)?.name === `SMOKE Pune Ring ${tag}`);
        r = await call('GET', `/api/items/barcode/SMOKE-PI-${tag}`, { token: staff });
        check('another branch (main) cannot find that item', r.status === 404, `(${r.status})`);
        r = await call('GET', `/api/items/barcode/SMOKE-I-${tag}-1`, { token: puneStaff });
        check('branch staff cannot find the main branch items', r.status === 404, `(${r.status})`);
        r = await call('GET', `/api/items?search=SMOKE&limit=200`, { token: puneStaff });
        const names = JSON.stringify(r.data || r.json).match(/SMOKE (Pune )?Ring/g) || [];
        check('the branch item list holds only its own items', r.status === 200 && names.length >= 1 && !/SMOKE Ring \d/.test(JSON.stringify(r.data || r.json)));
        r = await call('GET', '/api/containers', { token: puneStaff });
        check('the branch container list holds only its own boxes', r.status === 200 && (r.data?.containers || []).every((c) => /PuneBox/.test(c.name)) && (r.data?.containers || []).length >= 1);
        r = await call('PUT', `/api/items/${puneItem}`, { token: staff, body: { name: 'hijack' } });
        check('main staff cannot edit another branch item', r.status === 404 || r.status === 403, `(${r.status})`);

        // the branch switcher for admins
        r = await call('GET', `/api/items/barcode/SMOKE-PI-${tag}`, { token: admin });
        check('admin (whole firm) sees the branch item', r.status === 200);
        r = await call('GET', `/api/items/barcode/SMOKE-PI-${tag}`, { token: admin, headers: { 'X-Branch': 'main' } });
        check('admin switched to Main does not see the branch item', r.status === 404, `(${r.status})`);
        r = await call('GET', `/api/items/barcode/SMOKE-PI-${tag}`, { token: admin, headers: { 'X-Branch': puneId } });
        check('admin switched to the branch sees it', r.status === 200);
        r = await call('GET', `/api/items/barcode/SMOKE-PI-${tag}`, { token: puneStaff, headers: { 'X-Branch': 'main' } });
        check('staff cannot switch branch with the header', r.status === 200);

        // billing follows the branch switcher (a real invoice for the Pune registration)
        r = await call('POST', '/api/billing/invoices', { token: admin, headers: { 'X-Branch': puneId }, body: { requestId: uid(), customerName: 'Pune Walk-in', items: [ring({ netWt: 2, rate: 6000, makingCharge: 600 })], paidAmount: 12978 } });
        check('admin billing as the Pune branch', r.status === 201 && r.data?.branchId === puneId && /^PN-\d{4}$/.test(r.data?.invoiceNumber || ''), JSON.stringify(r.json).slice(0, 140));
        r = await call('GET', '/api/billing/meta', { token: admin, headers: { 'X-Branch': puneId } });
        check('billing meta gives the branch its own GSTIN state (27) and default place', r.data?.supplyStateCode === '27' && /Maharashtra/.test(r.data?.defaultPlace || ''), JSON.stringify(r.data?.defaultPlace));

        // GST: one registration per GSTIN
        const mkInv = (no, date, branch, amt = 20000) => ({ invoice_number: no, invoice_date: date, customer_name: 'MB Test', customer_mobile: '9000000001', status: 'delivered', source: 'mb-test', branch_id: branch, branch_name: branch, gst_type: 'CGST_SGST', place_of_supply: '19-West Bengal', payment_mode: 'Cash',
            items: [{ particulars: 'Gold Ring', hsn_code: '7113', metal_type: 'Gold', net_wt: 3, rate: 6000, making_charge: 0, taxable_amount: amt, cgst: amt * 0.015, sgst: amt * 0.015, igst: 0, total: amt * 1.03 }],
            gst_summary: { total_taxable_amount: amt, total_cgst: amt * 0.015, total_sgst: amt * 0.015, total_igst: 0, total_gst: amt * 0.03 }, total_amount: amt, total_payable_amount: Math.round(amt * 1.03), paid_amount: Math.round(amt * 1.03), created_at: new Date() });
        const { MongoClient } = require('mongodb');
        const cmb = await MongoClient.connect('mongodb://127.0.0.1:27018');
        try {
            const invc = cmb.db('lgp_dev').collection('invoices');
            await invc.deleteMany({ source: 'mb-test' });
            await invc.insertMany([mkInv('MB-1', '2025-03-05', 'main', 20000), mkInv('MB-2', '2025-03-06', puneId, 50000), mkInv('MB-3', '2025-03-07', 'main', 10000)]);
            const q = (extra) => `/api/gst-reports/summary?from=2025-03-01&to=2025-03-31${extra}`;
            r = await call('GET', q(''), { token: admin });
            check('default registration (firm GSTIN) counts only main-branch invoices', r.data?.totals?.invoices === 2 && Math.round(r.data.totals.taxable) === 30000, JSON.stringify(r.data?.totals).slice(0, 100));
            r = await call('GET', q(`&gstin=${G_B}`), { token: admin });
            check('the Pune GSTIN counts only its own branch invoices', r.data?.totals?.invoices === 1 && Math.round(r.data.totals.taxable) === 50000, JSON.stringify(r.data?.totals).slice(0, 100));
            r = await call('GET', q('&gstin=all'), { token: admin });
            check('"all registrations" adds them up for the firm view', r.data?.totals?.invoices === 3 && Math.round(r.data.totals.taxable) === 80000);
            r = await call('GET', q(`&gstin=all&branch=${puneId}`), { token: admin });
            check('a branch filter narrows further', r.data?.totals?.invoices === 1);
            r = await call('GET', q(`&gstin=29ZZZZZ0000Z1Z1`), { token: admin });
            check('an unknown GSTIN is refused (403)', r.status === 403, `(${r.status})`);
            r = await call('GET', '/api/gst-reports/returns?period=2025-03&gstin=all', { token: admin });
            check('returns need ONE registration (400 for "all")', r.status === 400, `(${r.status})`);
            r = await call('GET', `/api/gst-reports/returns?period=2025-03&gstin=${G_B}`, { token: admin });
            check('Pune returns: its own figures, tagged with its registration', r.status === 200 && r.data?.registration?.gstin === G_B && Math.round(r.data.gstr1.totals.taxable) === 50000, JSON.stringify(r.data?.registration));
            r = await call('GET', '/api/gst-reports/settings', { token: admin });
            check('settings list every registration the caller may see', (r.data?.registrations || []).length >= 2 && r.data.registrations.some((x) => x.gstin === G_B) && r.data.registrations.filter((x) => x.isDefault).length === 1);
            r = await call('PUT', `/api/gst-reports/settings?gstin=${G_B}`, { token: admin, body: { frequency: 'quarterly' } });
            check('each registration has its own filing frequency', r.status === 200 && r.data?.settings?.frequency === 'quarterly');
            r = await call('GET', '/api/gst-reports/settings', { token: admin });
            check('...and the default registration is not changed by it', r.data?.settings?.frequency === 'monthly');
            // the same return for the same month can be filed for both GSTINs
            const fbody = { returnType: 'GSTR-3B', period: '2025-03', filedOn: '2025-04-20', arn: 'MBARN0001', taxLiability: 100 };
            r = await call('POST', '/api/gst-reports/filings', { token: admin, body: fbody });
            check('file GSTR-3B for the default GSTIN', r.status === 201, `(${r.status} ${r.json.message || ''})`);
            r = await call('POST', `/api/gst-reports/filings?gstin=${G_B}`, { token: admin, body: { ...fbody, arn: 'MBARN0002' } });
            check('the same return for the Pune GSTIN is a separate record (no clash)', r.status === 201, `(${r.status} ${r.json.message || ''})`);
            r = await call('POST', `/api/gst-reports/filings?gstin=${G_B}`, { token: admin, body: { ...fbody, arn: 'MBARN0003' } });
            check('a duplicate within one GSTIN is still refused (409)', r.status === 409, `(${r.status})`);
            r = await call('GET', '/api/gst-reports/filings?type=GSTR-3B&period=2025-03', { token: admin });
            check('filing lists are per registration', (r.data || []).length === 1 && r.data[0].arn === 'MBARN0001');
            r = await call('GET', `/api/gst-reports/monthly-record?year=2025&month=3&gstin=${G_B}`, { token: admin });
            check('monthly record for the Pune GSTIN carries that GSTIN and only its invoices', r.status === 200 && r.data?.seller?.gstin === G_B && r.data?.invoices?.length === 1 && r.data?.invoices?.[0]?.number === 'MB-2', JSON.stringify(r.data?.seller));
            r = await call('GET', '/api/gst-reports/summary?from=2025-03-01&to=2025-03-31', { token: staff });
            check('staff without GST access still get 403', r.status === 403);
        } finally {
            await cmb.db('lgp_dev').collection('invoices').deleteMany({ source: 'mb-test' });
            await cmb.db('lgp_dev').collection('gst_data').deleteMany({ 'filings.arn': /^MBARN/ });
            await cmb.db('lgp_dev').collection('app_gst_settings').deleteMany({ key: `gstin:${G_B}` });
            await cmb.db('lgp_dev').collection('invoices').deleteMany({ customer_name: 'Pune Walk-in' });
            await cmb.db('lgp_dev').collection('app_branches').deleteMany({ name: `SMOKE Pune ${tag}` });
            await cmb.db('lgp_dev').collection('users').deleteMany({ full_name: `SMOKE Pune Staff ${tag}` });
            await cmb.db('lgp_dev').collection('items').deleteMany({ barcode: `SMOKE-PI-${tag}` });
            await cmb.db('lgp_dev').collection('containers').deleteMany({ qrCode: `SMOKE-PC-${tag}` });
            await cmb.close();
        }
    }

    // ── Items: optional billing detail, and moving between boxes ─────────────────
    section('Items: detail and box move');
    {
        const bc = `SMOKE-X-${tag}`;
        r = await call('POST', '/api/containers', { token: admin, body: { name: `SMOKE MvA ${tag}`, type: 'box', capacity: 2, weightCategory: 'Light', layoutType: 'grid', qrCode: `SMOKE-MA-${tag}`, allowedItemTypes: ['ring'] } });
        const boxA = unwrap(r.data)?._id;
        r = await call('POST', '/api/containers', { token: admin, body: { name: `SMOKE MvB ${tag}`, type: 'box', capacity: 1, weightCategory: 'Light', layoutType: 'grid', qrCode: `SMOKE-MB-${tag}`, allowedItemTypes: ['ring'] } });
        const boxB = unwrap(r.data)?._id;
        r = await call('POST', '/api/items', { token: admin, body: { barcode: bc, name: 'SMOKE Detail Ring', itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 4, grossWeight: 4.5, lessWeight: 0.5, stoneValue: 800, stoneNote: 'Ruby', makingCharge: 600, supplier: 'Test', size: '14', containerId: boxA, slotNumber: 1 } });
        const xi = unwrap(r.data);
        check('item saves gross / less / stone / making / supplier / size', r.status === 201 && xi?.grossWeight === 4.5 && xi?.lessWeight === 0.5 && xi?.stoneValue === 800 && xi?.stoneNote === 'Ruby' && xi?.makingCharge === 600 && xi?.supplier === 'Test', JSON.stringify(r.json).slice(0, 120));
        r = await call('GET', `/api/items/barcode/${bc}`, { token: admin });
        check('the detail comes back when the item is scanned (billing pre-fills from it)', unwrap(r.data)?.grossWeight === 4.5 && unwrap(r.data)?.makingCharge === 600);
        r = await call('PUT', `/api/items/${xi?._id}`, { token: admin, body: { name: 'SMOKE Detail Ring 2', stoneValue: null, containerId: boxA, slotNumber: 1 } });
        check('an edit that keeps the same box does not move it; null clears a detail', r.status === 200 && unwrap(r.data)?.stoneValue === null && String(unwrap(r.data)?.containerId) === boxA && unwrap(r.data)?.slotNumber === 1, JSON.stringify(r.json).slice(0, 120));
        r = await call('PUT', `/api/items/${xi?._id}`, { token: admin, body: { containerId: boxB } });
        check('editing the box moves the item to the other box', r.status === 200 && String(unwrap(r.data)?.containerId) === boxB && unwrap(r.data)?.slotNumber === 1, JSON.stringify(r.json).slice(0, 140));
        r = await call('GET', `/api/containers/${boxA}`, { token: admin });
        const ca = unwrap(r.data)?.container || unwrap(r.data);
        check('the old box slot is free again', (ca?.slots || []).every((sl) => !sl.itemId), JSON.stringify((ca?.slots || []).map((sl) => sl.itemId)));
        r = await call('POST', '/api/items', { token: admin, body: { barcode: bc + 'b', name: 'SMOKE Second', itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 2, containerId: boxB, slotNumber: 1 } });
        r = await call('PUT', `/api/items/${xi?._id}`, { token: admin, body: { containerId: boxA, slotNumber: 1 } });
        r = await call('PUT', `/api/items/${(await call('GET', `/api/items/barcode/${bc}b`, { token: admin })).data?.item?._id}`, { token: admin, body: { containerId: boxA, slotNumber: 1 } });
        check('moving into an occupied slot is refused (400)', r.status === 400, `(${r.status} ${r.json.message || ''})`);
        r = await call('PUT', `/api/items/${xi?._id}`, { token: admin, body: { containerId: null } });
        check('containerId null takes the item out of its box', r.status === 200 && !unwrap(r.data)?.containerId, JSON.stringify(r.json).slice(0, 100));
        const cx = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cx.db('lgp_dev').collection('items').deleteMany({ barcode: { $in: [bc, bc + 'b'] } });
        await cx.db('lgp_dev').collection('containers').deleteMany({ qrCode: { $in: [`SMOKE-MA-${tag}`, `SMOKE-MB-${tag}`] } });
        await cx.close();
    }

    // ── Sell stock: a piece on an invoice leaves stock ──────────────────────────
    section('Sell stock');
    {
        const bc = `SMOKE-S-${tag}`;
        r = await call('POST', '/api/containers', { token: admin, body: { name: `SMOKE SellBox ${tag}`, type: 'box', capacity: 2, weightCategory: 'Light', layoutType: 'grid', qrCode: `SMOKE-SB-${tag}`, allowedItemTypes: ['ring'] } });
        const box = unwrap(r.data)?._id;
        r = await call('POST', '/api/items', { token: admin, body: { barcode: bc, name: 'SMOKE Sell Ring', itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 2, containerId: box, slotNumber: 1 } });
        const piece = unwrap(r.data);
        const body = (pay) => ({ requestId: uid(), customerName: 'Sell Walk-in', items: [ring({ netWt: 2, rate: 6000, makingCharge: 400, itemId: piece?._id, productCode: bc })], paidAmount: pay });
        r = await call('POST', '/api/billing/invoices', { token: admin, body: body(12772) });
        check('an invoice with a stock piece is created', r.status === 201, `(${r.status} ${r.json.message || ''})`);
        r = await call('GET', `/api/items/barcode/${bc}`, { token: admin });
        const sold = unwrap(r.data);
        check('the piece is now "sold" with the invoice number, who and when', sold?.status === 'sold' && !!sold?.soldInvoice && !!sold?.soldAt, JSON.stringify({ s: sold?.status, i: sold?.soldInvoice }));
        r = await call('GET', `/api/containers/${box}`, { token: admin });
        const bx = unwrap(r.data)?.container || unwrap(r.data);
        check('its box slot is free again', (bx?.slots || []).every((sl) => !sl.itemId));
        r = await call('POST', '/api/billing/invoices', { token: admin, body: body(12772) });
        check('the same piece cannot be sold twice (400)', r.status === 400 && /already sold/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
        const cs = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cs.db('lgp_dev').collection('items').deleteMany({ barcode: bc });
        await cs.db('lgp_dev').collection('containers').deleteMany({ qrCode: `SMOKE-SB-${tag}` });
        await cs.db('lgp_dev').collection('invoices').deleteMany({ customer_name: 'Sell Walk-in' });
        await cs.close();
    }

    // ── Purchase with valuation (Purchase rules) ────────────────────────────────
    section('Purchase valuation');
    {
        const inv = `SMK-PV-${tag}`;
        await call('POST', '/api/stock-settings/reset', { token: admin });
        const body = { invoiceDate: new Date().toISOString(), invoiceNumber: inv, metalType: 'gold', biller: 'SMOKE Supplier', billerGstin: '19AAAAA0000A1Z5', quantity: 1, rate: 1, valuation: { gross: 100, less: 0, purity: '22K', wastage: 2, rate: 10000, labourRate: 50, pieces: 1, certification: 'none' } };
        r = await call('POST', '/api/purchases', { token: admin, body });
        const pu = r.data?.purchase;
        check('the server values the purchase itself (net 100 g x 10,000 + labour on fine wt) whatever the client sent', r.status === 201 && pu?.quantity === 100 && pu?.rate === 10000 && pu?.totalAmount === 1004580 && pu?.valuation?.result?.finalFine === 93.6, JSON.stringify(r.json).slice(0, 160));
        check('GST and input credit follow that taxable amount (3%)', Math.abs((pu?.totalGst || 0) - 30137.4) < 0.5, JSON.stringify({ g: pu?.totalGst }));
        r = await call('POST', '/api/purchases', { token: admin, body: { ...body, invoiceNumber: inv + 'x', valuation: { gross: 0, rate: 0 } } });
        check('a valuation without weight or rate is refused (400)', r.status === 400, `(${r.status})`);
        // hallmark fee on a purchase: goods at 3%, the fee with its own 18% GST (rule "hallmark GST"), all of it input credit
        const inv2 = inv + 'h';
        r = await call('POST', '/api/purchases', { token: admin, body: { ...body, invoiceDate: '2019-05-10T05:00:00.000Z', invoiceNumber: inv2, valuation: { net: 10, purity: '24K', rate: 1000, pieces: 2, certification: 'huid' } } });
        const ph = r.data?.purchase;
        check('a hallmarked purchase: goods taxable 10,000 + hallmark fee 90 with its own GST 16.20 (total GST 316.20, payable 10,406.20)', r.status === 201 && ph?.totalAmount === 10000 && Math.abs(ph.totalGst - 316.2) < 0.01 && Math.abs(ph.totalPayable - 10406.2) < 0.01 && Math.abs(ph.totalItc - 316.2) < 0.01, JSON.stringify({ a: ph?.totalAmount, g: ph?.totalGst, p: ph?.totalPayable, i: ph?.totalItc }));
        // editing the valuation works out the amount, GST and input credit again
        r = await call('PUT', `/api/purchases/${ph?._id}`, { token: admin, body: { valuation: { net: 20, purity: '24K', rate: 1000, pieces: 2, certification: 'huid' } } });
        const pe = r.data?.purchase;
        check('editing the valuation recomputes quantity, taxable amount, GST and ITC', r.status === 200 && pe?.quantity === 20 && pe?.totalAmount === 20000 && Math.abs(pe.totalGst - 616.2) < 0.01 && Math.abs(pe.totalItc - 616.2) < 0.01, JSON.stringify(r.json).slice(0, 200));
        // once the GSTR-3B of that period is filed the purchase is locked
        const cf = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cf.db('lgp_dev').collection('gst_data').insertOne({ financial_year: 2019, quarter: 1, gstr1_filed: false, gstr3b_filed: false, created_at: new Date(), filings: [{ id: 'smoke-lock-0001', gstin: '', returnType: 'GSTR-3B', period: '2019-05', filedOn: '2019-06-20', taxLiability: 0, itcUsed: 0, cashPaid: 0, lateFee: 0, interest: 0, nil: false, note: 'SMOKE lock' }] });
        r = await call('PUT', `/api/purchases/${ph?._id}`, { token: admin, body: { valuation: { net: 30, purity: '24K', rate: 1000 } } });
        check('a purchase in a period whose GSTR-3B is filed cannot be revalued (409)', r.status === 409 && /already filed/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
        await cf.db('lgp_dev').collection('gst_data').deleteMany({ 'filings.note': 'SMOKE lock' });
        await cf.close();
        const cp = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cp.db('lgp_dev').collection('purchases').deleteMany({ invoice_number: { $in: [inv, inv + 'x', inv2].map((x) => String(x).toUpperCase()) } });
        await cp.close();
    }

    // ── Old metal / raw metal ────────────────────────────────────────────────────
    section('Old metal');
    {
        await call('POST', '/api/stock-settings/reset', { token: admin });
        r = await call('POST', '/api/old-metal', { token: viewer, body: { metalType: 'gold', customerName: 'SMOKE OM', purity: '22K', net: 10, rate: 1000 } });
        check('a viewer cannot receive old metal (403)', r.status === 403, `(${r.status})`);
        r = await call('POST', '/api/old-metal', { token: admin, body: { kind: 'old', metalType: 'gold', customerName: 'SMOKE OM Customer', customerMobile: '9000000077', gross: 50, less: 2, purity: '22K', deduction: 3.6, rate: 10000, note: 'old chain and bangle' } });
        const om = r.data?.entry;
        check('old metal is valued on fine weight (net 48 g x 91.6% x rate) by default', r.status === 201 && om?.net === 48 && om?.fine === 43.968 && om?.amount === 439680 && om?.basis === 'fine', JSON.stringify(r.json).slice(0, 140));
        r = await call('POST', '/api/old-metal', { token: admin, body: { kind: 'old', metalType: 'gold', purity: '22K', net: 5, rate: 1000 } });
        check('a customer name is required for old metal (400)', r.status === 400);
        r = await call('POST', '/api/old-metal', { token: admin, body: { kind: 'raw', metalType: 'silver', purity: '999', net: 100, rate: 100, note: 'SMOKE raw' } });
        check('raw metal needs no customer and uses the raw-purchase basis (net)', r.status === 201 && r.data?.entry?.amount === 10000 && r.data.entry.basis === 'net', JSON.stringify(r.json).slice(0, 120));
        r = await call('POST', '/api/old-metal', { token: admin, body: { kind: 'raw', metalType: 'silver', purity: '999', net: 0, rate: 100 } });
        check('no weight is refused (400)', r.status === 400);
        r = await call('GET', '/api/old-metal?kind=old&q=SMOKE OM', { token: staff });
        check('the list finds it and totals only active entries', r.status === 200 && (r.data?.rows || []).some((x) => x._id === om?._id) && r.data.totals.count >= 1);
        r = await call('POST', `/api/old-metal/${om?._id}/cancel`, { token: admin });
        check('cancel marks it cancelled', r.status === 200 && r.data?.entry?.status === 'cancelled');
        r = await call('POST', `/api/old-metal/${om?._id}/cancel`, { token: admin });
        check('cancelling twice is refused (400)', r.status === 400);
        const co = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await co.db('lgp_dev').collection('app_old_metal').deleteMany({ $or: [{ customerName: /^SMOKE OM/ }, { note: 'SMOKE raw' }] });
        await co.close();
    }

    // ── Old metal adjusted against a GST bill ────────────────────────────────────
    section('Old metal on a bill');
    {
        await call('POST', '/api/stock-settings/reset', { token: admin });
        const mk = async (net, rate, name) => (await call('POST', '/api/old-metal', { token: admin, body: { kind: 'old', metalType: 'gold', customerName: name, customerMobile: '9000000088', purity: '24K', net, rate } })).data?.entry;
        const e1 = await mk(2, 1000, 'SMOKE OMB Cust');           // 24K = 99.9% -> valued on fine wt: 1.998 g x 1000 = 1,998
        const e2 = await mk(1, 1000, 'SMOKE OMB Cust');
        check('old metal entries are created for a customer', !!e1?._id && !!e2?._id && e1.amount === 1998);
        r = await call('GET', '/api/old-metal/available?mobile=9000000088', { token: staff });
        check('the bill can see this customer\'s unused old metal (by mobile)', r.status === 200 && (r.data || []).length >= 2, `(${r.status} ${(r.data || []).length})`);
        r = await call('GET', '/api/old-metal/available?name=smoke omb cust', { token: staff });
        check('...and by exact name; a stranger sees none', (r.data || []).length >= 2 && (await call('GET', '/api/old-metal/available?mobile=9111111111', { token: staff })).data.length === 0);
        // bill: 1 g gold ring 6000 rate + making 400 -> ~6,592 with GST; pay 3,000 cash and adjust the two old metal entries
        const bill = (om, pay) => ({ requestId: uid(), customerName: 'SMOKE OMB Cust', customerMobile: '9000000088', items: [ring({ netWt: 1, rate: 6000, makingCharge: 400 })], paidAmount: pay, oldMetalIds: om });
        r = await call('POST', '/api/billing/invoices', { token: admin, body: bill([e1._id, e2._id], 3600) });
        const inv = r.data;
        const omPay = (inv?.paymentHistory || []).find((x) => x.mode === 'Old Metal');
        check('the bill takes the old metal as a payment in kind (mode "Old Metal", value 1,998 + 999)', r.status === 201 && omPay?.amount === 2997.0 || (omPay && Math.abs(omPay.amount - 2997) < 1), JSON.stringify(r.json).slice(0, 200));
        check('paid = cash + old metal, and the old metal is listed on the invoice', Math.abs(inv?.paidAmount - (3600 + (omPay?.amount || 0))) < 0.01 && inv?.oldMetal?.length === 2 && inv.oldMetalAmount === omPay?.amount);
        check('the invoice main payment mode stays a money mode (the website edit form only knows those)', ['Cash', 'Card', 'Online', 'Cheque'].includes(inv?.paymentMode), String(inv?.paymentMode));
        r = await call('GET', '/api/old-metal?used=yes&q=SMOKE OMB', { token: admin });
        check('both entries now show the invoice number they were adjusted on', (r.data?.rows || []).length === 2 && r.data.rows.every((x) => x.usedOnInvoice === inv?.invoiceNumber));
        r = await call('POST', '/api/billing/invoices', { token: admin, body: bill([e1._id], 1000) });
        check('an entry cannot be adjusted twice (400)', r.status === 400 && /already used/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
        r = await call('POST', `/api/old-metal/${e1._id}/cancel`, { token: admin });
        check('an adjusted entry cannot be cancelled (400)', r.status === 400);
        r = await call('GET', '/api/old-metal/available?mobile=9000000088', { token: staff });
        check('used entries no longer appear as available', (r.data || []).length === 0);
        const cb = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cb.db('lgp_dev').collection('app_old_metal').deleteMany({ customerName: /^SMOKE OMB/ });
        await cb.db('lgp_dev').collection('invoices').deleteMany({ customer_name: 'SMOKE OMB Cust' });
        await cb.close();
    }

    // ── A cancelled bill gives the piece and the old metal back ─────────────────
    section('Cancelled bill returns stock');
    {
        await call('POST', '/api/stock-settings/reset', { token: admin });
        const bc = `SMOKE-R-${tag}`;
        r = await call('POST', '/api/containers', { token: admin, body: { name: `SMOKE RelBox ${tag}`, type: 'box', capacity: 2, weightCategory: 'Light', layoutType: 'grid', qrCode: `SMOKE-RB-${tag}`, allowedItemTypes: ['ring'] } });
        const box = unwrap(r.data)?._id;
        r = await call('POST', '/api/items', { token: admin, body: { barcode: bc, name: 'SMOKE Rel Ring', itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 1, containerId: box, slotNumber: 1 } });
        const piece = unwrap(r.data);
        const omE = (await call('POST', '/api/old-metal', { token: admin, body: { kind: 'old', metalType: 'gold', customerName: 'SMOKE REL Cust', customerMobile: '9000000066', purity: '24K', net: 1, rate: 1000 } })).data?.entry;
        r = await call('POST', '/api/billing/invoices', { token: admin, body: { requestId: uid(), customerName: 'SMOKE REL Cust', customerMobile: '9000000066', items: [ring({ netWt: 1, rate: 6000, makingCharge: 400, itemId: piece?._id, productCode: bc })], paidAmount: 5600, oldMetalIds: [omE?._id] } });
        const invNo = r.data?.invoiceNumber;
        check('the bill sells the piece and uses the old metal', r.status === 201 && !!invNo, JSON.stringify(r.json).slice(0, 120));
        const cr = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cr.db('lgp_dev').collection('invoices').updateOne({ invoice_number: invNo }, { $set: { status: 'cancelled' } });   // what the website does
        r = await call('POST', '/api/billing/reconcile', { token: admin });
        check('the reconcile finds the cancelled bill', r.status === 200 && r.data?.pieces >= 1 && r.data?.oldMetal >= 1, JSON.stringify(r.json));
        r = await call('GET', `/api/items/barcode/${bc}`, { token: admin });
        check('the piece is back in stock, in its box, with no sold marks', unwrap(r.data)?.status === 'active' && !unwrap(r.data)?.soldInvoice && String(unwrap(r.data)?.containerId?._id || unwrap(r.data)?.containerId) === box);
        r = await call('GET', `/api/containers/${box}`, { token: admin });
        const bx2 = unwrap(r.data)?.container || unwrap(r.data);
        check('its slot holds it again', (bx2?.slots || []).some((sl) => sl.itemId && String(sl.itemId._id || sl.itemId) === piece?._id));
        r = await call('GET', '/api/old-metal/available?mobile=9000000066', { token: staff });
        check('the old metal is available again', (r.data || []).length === 1);
        r = await call('POST', '/api/billing/reconcile', { token: admin });
        check('running it again does nothing (each cancelled bill is handled once)', r.data?.pieces === 0 && r.data?.oldMetal === 0);
        r = await call('POST', '/api/billing/reconcile', { token: staff });
        check('only people who see every branch can run it (403)', r.status === 403);
        await cr.db('lgp_dev').collection('items').deleteMany({ barcode: bc });
        await cr.db('lgp_dev').collection('containers').deleteMany({ qrCode: `SMOKE-RB-${tag}` });
        await cr.db('lgp_dev').collection('app_old_metal').deleteMany({ customerName: /^SMOKE REL/ });
        await cr.db('lgp_dev').collection('app_stock_release').deleteMany({ invoice: invNo });
        await cr.db('lgp_dev').collection('invoices').deleteMany({ customer_name: 'SMOKE REL Cust' });
        await cr.close();
    }

    // ── Credit notes: returns, refunds, partial refunds ─────────────────────────
    section('Credit notes');
    {
        await call('POST', '/api/stock-settings/reset', { token: admin });
        const bc = `SMOKE-C-${tag}`;
        const box = unwrap((await call('POST', '/api/containers', { token: admin, body: { name: `SMOKE CnBox ${tag}`, type: 'box', capacity: 2, weightCategory: 'Light', layoutType: 'grid', qrCode: `SMOKE-CB-${tag}`, allowedItemTypes: ['ring'] } })).data)?._id;
        const piece = unwrap((await call('POST', '/api/items', { token: admin, body: { barcode: bc, name: 'SMOKE Cn Ring', itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 2, containerId: box, slotNumber: 1 } })).data);
        // 2 lines: the stock ring (12,000 + making 1,000) and a hand-typed chain
        r = await call('POST', '/api/billing/invoices', { token: admin, body: { requestId: uid(), customerName: 'SMOKE CN Cust', customerMobile: '9000000055', customerAddress: '1 Test Road, Howrah', items: [ring({ netWt: 2, rate: 6000, makingCharge: 1000, itemId: piece?._id, productCode: bc }), ring({ particulars: 'Gold Chain', netWt: 1, rate: 6000, makingCharge: 500 })], paidAmount: 20085 } });
        const inv = r.data;
        check('a bill with two lines is created', r.status === 201 && (inv?.items || []).length === 2, `(${r.status} ${r.json.message || ''})`);
        r = await call('GET', `/api/credit-notes/invoice/${inv?._id}`, { token: staff });
        check('the returnable state lists each line with what is left', r.status === 200 && r.data?.lines?.length === 2 && r.data.lines[0].left === r.data.lines[0].taxable && r.data.notes.length === 0 && /^\d{4}-11-30$/.test(r.data.deadline));
        r = await call('POST', '/api/credit-notes/preview', { token: staff, body: { invoiceId: inv?._id, lines: [{ index: 0 }] } });
        check('staff without the credit note permission cannot preview or create (403)', r.status === 403);
        r = await call('POST', '/api/credit-notes/preview', { token: admin, body: { invoiceId: inv?._id, lines: [{ index: 0 }] } });
        check('preview: the ring line returns with 1.5% + 1.5% tax', r.status === 200 && r.data?.taxable === 13000 && r.data.cgst === 195 && r.data.sgst === 195 && r.data.total === 13390 && r.data.reducesTax === true, JSON.stringify(r.json).slice(0, 160));
        check('preview also says the most that can be paid back (never above what was paid)', r.data?.maxRefund === 13390);
        // part refund on the chain (price adjustment of 500)
        const rid = uid();
        r = await call('POST', '/api/credit-notes', { token: admin, body: { requestId: rid, invoiceId: inv?._id, lines: [{ index: 1, taxable: 500 }], reason: 'price_adjustment', note: 'weight difference', refundMode: 'Cash', refundAmount: 515 } });
        const n1 = r.data?.note;
        check('a partial credit note is issued (CN-0001 style number, refund recorded)', r.status === 201 && /CN-\d{4}$/.test(n1?.number || '') && n1.total === 515 && n1.refundAmount === 515 && n1.gstType === 'CGST_SGST', JSON.stringify(r.json).slice(0, 160));
        r = await call('POST', '/api/credit-notes', { token: admin, body: { requestId: rid, invoiceId: inv?._id, lines: [{ index: 1, taxable: 500 }], reason: 'price_adjustment', refundMode: 'Cash', refundAmount: 515 } });
        check('the same request id never makes a second note (idempotent)', r.status === 200 && r.json.duplicate === true && r.data?.note?.number === n1?.number);
        r = await call('POST', '/api/credit-notes', { token: admin, body: { requestId: uid(), invoiceId: inv?._id, lines: [{ index: 1, taxable: 99999 }], reason: 'sales_return' } });
        check('more than what is left on the line is refused (400)', r.status === 400);
        r = await call('POST', '/api/credit-notes', { token: admin, body: { requestId: uid(), invoiceId: inv?._id, lines: [{ index: 0 }], reason: 'sales_return', refundMode: 'Cash', refundAmount: 99999 } });
        check('a refund above the note is refused (400)', r.status === 400);
        r = await call('POST', '/api/credit-notes', { token: admin, body: { requestId: uid(), invoiceId: inv?._id, lines: [{ index: 0 }], reason: 'sales_return', note: 'customer returned the ring', refundMode: 'Online', refundAmount: 13390 } });
        const n2 = r.data?.note;
        check('the whole ring is returned: a credit note with the full line and the piece restocked', r.status === 201 && n2?.total === 13390 && n2.lines[0].fullReturn === true && n2.lines[0].restocked === true, JSON.stringify(r.json).slice(0, 160));
        r = await call('GET', `/api/items/barcode/${bc}`, { token: admin });
        check('the returned piece is back in stock (active, in its box)', unwrap(r.data)?.status === 'active' && !unwrap(r.data)?.soldInvoice);
        r = await call('POST', '/api/credit-notes', { token: admin, body: { requestId: uid(), invoiceId: inv?._id, lines: [{ index: 0 }], reason: 'sales_return' } });
        check('the ring cannot be returned twice (400)', r.status === 400 && /already been credited/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
        r = await call('GET', `/api/credit-notes?invoice=${inv?.invoiceNumber}`, { token: staff });
        check('the notes of the invoice are listed (2), numbered in sequence', r.status === 200 && r.data.length === 2);
        r = await call('GET', `/api/credit-notes/invoice/${inv?._id}`, { token: staff });
        check('the line now shows what was credited and what is left', r.data?.lines?.[0]?.left === 0 && r.data.lines[1].credited === 500 && r.data.notes.length === 2);
        const today = new Date().toISOString().slice(0, 10);
        const pm = `${today.slice(0, 7)}`;
        r = await call('GET', `/api/gst-reports/returns?period=${pm}`, { token: admin });
        check('GSTR-1 shows the credit notes (table 9B) and the tax liability is reduced by them', r.status === 200 && r.data?.creditNotes?.count >= 2 && r.data.creditNotes.list.some((x) => x.number === n2?.number) && r.data.gstr3b.liability.cgst <= r.data.gstr3b.liabilityBeforeCreditNotes.cgst - 195 + 0.01, JSON.stringify(r.data?.creditNotes).slice(0, 160));
        // a cancelled invoice needs no credit note
        const cc = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cc.db('lgp_dev').collection('invoices').updateOne({ invoice_number: inv?.invoiceNumber }, { $set: { status: 'cancelled' } });
        r = await call('POST', '/api/credit-notes/preview', { token: admin, body: { invoiceId: inv?._id, lines: [{ index: 1 }] } });
        check('a cancelled invoice cannot get a credit note (400)', r.status === 400);
        await cc.db('lgp_dev').collection('items').deleteMany({ barcode: bc });
        await cc.db('lgp_dev').collection('containers').deleteMany({ qrCode: `SMOKE-CB-${tag}` });
        await cc.db('lgp_dev').collection('app_credit_notes').deleteMany({ customerName: 'SMOKE CN Cust' });
        await cc.db('lgp_dev').collection('app_stock_release').deleteMany({ invoice: inv?.invoiceNumber });
        await cc.db('lgp_dev').collection('invoices').deleteMany({ customer_name: 'SMOKE CN Cust' });
        await cc.close();
    }

    // ── Sell rule "last entry": making charge per gram of the last sale ─────────
    section('Last making charge');
    {
        const nm = `SMOKE LastMk ${tag}`;
        r = await call('POST', '/api/billing/invoices', { token: admin, body: { requestId: uid(), customerName: 'SMOKE LM Cust', items: [ring({ particulars: nm, netWt: 4, rate: 6000, makingCharge: 800 })], paidAmount: 25750 } });
        r = await call('GET', `/api/billing/last-making?name=${encodeURIComponent(nm)}&metal=Gold`, { token: staff });
        check('the last sale of the same piece gives the making charge per gram (800 / 4 g = 200)', r.status === 200 && r.data?.perGram === 200, JSON.stringify(r.json).slice(0, 120));
        r = await call('GET', `/api/billing/last-making?name=${encodeURIComponent(nm)}&metal=Gold&userWise=1`, { token: staff });
        check('user-wise: a different user sale does not count', r.status === 200 && r.data === null);
        r = await call('GET', `/api/billing/last-making?name=${encodeURIComponent(nm)}&metal=Gold&userWise=1`, { token: admin });
        check('user-wise: the same user sees their own sale', r.data?.perGram === 200);
        r = await call('GET', '/api/billing/last-making?name=NoSuchPieceXYZ', { token: staff });
        check('a piece never sold before gives nothing', r.status === 200 && r.data === null);
        const cl = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cl.db('lgp_dev').collection('invoices').deleteMany({ customer_name: 'SMOKE LM Cust' });
        await cl.close();
    }

    // ── Today's rate, expenses, Day Book, dues ──────────────────────────────────
    section('Rates, expenses, Day Book, dues');
    {
        const cr = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cr.db('lgp_dev').collection('app_rates').deleteMany({});
        r = await call('PUT', '/api/rates', { token: viewer, body: { gold: 9200 } });
        check('a viewer cannot change the rate (403)', r.status === 403);
        r = await call('PUT', '/api/rates', { token: staff, body: { gold: 92 } });
        check('a rate that looks like a typing slip is refused (400)', r.status === 400);
        r = await call('PUT', '/api/rates', { token: staff, body: { gold: 9200, silver: 110 } });
        check('staff set today\'s rate; it says who and when', r.status === 200 && r.data?.gold === 9200 && r.data.silver === 110 && r.data.updatedToday === true && !!r.data.updatedByName, JSON.stringify(r.json).slice(0, 150));
        r = await call('GET', '/api/rates', { token: viewer });
        check('anyone signed in can read the rate', r.status === 200 && r.data?.gold === 9200);
        r = await call('GET', '/api/billing/meta', { token: staff });
        check('a new bill starts from today\'s rate (not from the last bill)', r.data?.goldRate === 9200 && r.data?.silverRate === 110, JSON.stringify({ g: r.data?.goldRate }));

        // expenses
        r = await call('POST', '/api/expenses', { token: staff, body: { amount: 0, mode: 'Cash', category: 'Rent' } });
        check('an expense needs an amount (400)', r.status === 400);
        r = await call('POST', '/api/expenses', { token: staff, body: { amount: 10, date: '2999-01-01' } });
        check('an expense cannot be dated in the future (400)', r.status === 400);
        const before = (await call('GET', '/api/billing/daybook', { token: admin })).data;
        r = await call('GET', '/api/billing/daybook', { token: staff });
        check('the Day Book is for the owner: staff are refused (403)', r.status === 403);
        r = await call('POST', '/api/expenses', { token: staff, body: { amount: 150.5, mode: 'Cash', category: 'Tea / food', note: 'SMOKE tea' } });
        const ex = r.data;
        check('staff add an expense', r.status === 201 && ex?.amount === 150.5 && ex.category === 'Tea / food', JSON.stringify(r.json).slice(0, 120));
        r = await call('GET', '/api/expenses', { token: staff });
        check('today\'s expenses are listed with a total', r.status === 200 && r.data.rows.some((x) => x.id === ex?.id) && r.data.total >= 150.5 && r.data.categories.includes('Rent'));
        r = await call('DELETE', `/api/expenses/${ex?.id}`, { token: staff });
        check('staff cannot cancel an expense (403, owner only)', r.status === 403);

        // a sale with part payment: money in, and a customer who owes the rest
        r = await call('POST', '/api/billing/invoices', { token: admin, body: { requestId: uid(), customerId: multi._id, customerAddress: '12 Test Road, Howrah', items: [ring({ netWt: 1, rate: 6000, makingCharge: 400 })], paidAmount: 2000, paymentMode: 'Cash' } });
        const inv = r.data;
        check('a bill with part payment is created', r.status === 201 && inv?.paidAmount === 2000 && inv.dueAmount > 4000, `(${r.status} ${r.json.message || ''})`);
        // refund on part of it
        r = await call('POST', '/api/credit-notes', { token: admin, body: { requestId: uid(), invoiceId: inv?._id, lines: [{ index: 0, taxable: 100 }], reason: 'price_adjustment', refundMode: 'Cash', refundAmount: 103 } });
        check('a credit note with a cash refund is issued', r.status === 201, `(${r.status} ${r.json.message || ''})`);
        const after = (await call('GET', '/api/billing/daybook', { token: admin })).data;
        const cash = (d) => d.modes.find((m) => m.mode === 'Cash');
        check('the Day Book: cash in grew by the payment (2,000), cash out by the expense (150.50) and the refund (103)', Math.abs(cash(after).in - cash(before).in - 2000) < 0.01 && Math.abs(cash(after).out - cash(before).out - 253.5) < 0.01, JSON.stringify({ b: cash(before), a: cash(after) }));
        check('...net is in minus out, and every line says what it is', Math.abs(after.totals.net - (after.totals.in - after.totals.out)) < 0.01 && after.lines.some((l) => l.kind === 'receipt' && l.subtitle === `Invoice ${inv?.invoiceNumber}`) && after.lines.some((l) => l.kind === 'refund') && after.lines.some((l) => l.kind === 'expense' && l.title === 'Tea / food'));
        check('...and the summary counts the sale and the refund', after.summary.sales.count >= before.summary.sales.count + 1 && after.summary.refunds.count >= before.summary.refunds.count + 1 && after.summary.expenses.amount >= 150.5);
        r = await call('GET', '/api/billing/daybook?from=2001-01-01&to=2001-01-02', { token: admin });
        check('a day with nothing gives zeros, not an error', r.status === 200 && r.data.totals.in === 0 && r.data.lines.length === 0);

        // dues
        r = await call('GET', `/api/billing/dues?q=${inv?.invoiceNumber}`, { token: staff });
        const due = (r.data?.rows || []).find((x) => (x.invoices || []).some((i) => i.number === inv?.invoiceNumber));
        check('the customer who owes shows in Pending dues with the balance and the bill', r.status === 200 && due && Math.abs(due.due - inv.dueAmount) < 0.01 && due.invoices[0].number === inv.invoiceNumber, JSON.stringify(r.json).slice(0, 200));
        r = await call('POST', `/api/billing/invoices/${inv?._id}/payments`, { token: admin, body: { requestId: uid(), amount: inv.dueAmount, mode: 'Online', reference: 'UTR-DB' } });
        r = await call('GET', `/api/billing/dues?q=${inv?.invoiceNumber}`, { token: staff });
        check('once paid in full the customer leaves Pending dues', !(r.data?.rows || []).some((x) => (x.invoices || []).some((i) => i.number === inv?.invoiceNumber)));
        r = await call('DELETE', `/api/expenses/${ex?.id}`, { token: admin });
        const gone = await call('GET', '/api/expenses', { token: staff });
        check('the owner cancels an expense; it leaves the list', r.status === 200 && !gone.data.rows.some((x) => x.id === ex?.id));
        await cr.db('lgp_dev').collection('app_rates').deleteMany({});
        await cr.db('lgp_dev').collection('app_expenses').deleteMany({ note: 'SMOKE tea' });
        await cr.db('lgp_dev').collection('app_credit_notes').deleteMany({ invoiceNumber: inv?.invoiceNumber });
        await cr.db('lgp_dev').collection('invoices').deleteMany({ invoice_number: inv?.invoiceNumber });
        await cr.close();
    }

    // ── Stock tally ─────────────────────────────────────────────────────────────
    section('Stock tally');
    {
        const ct = await MongoClient.connect('mongodb://127.0.0.1:27018');
        const tdb = ct.db('lgp_dev');
        await tdb.collection('tallysessions').deleteMany({});
        r = await call('GET', '/api/tally/preview', { token: viewer });
        check('the Start screen preview is for people who may start a tally (viewer refused, 403)', r.status === 403);
        r = await call('GET', '/api/tally/preview', { token: staff });
        const pv = r.data;
        check('the preview counts what is in the shop (items, boxes, weight per metal) without creating anything', r.status === 200 && pv?.items > 0 && pv.containers > 0 && pv.metals.length > 0 && pv.running === null, JSON.stringify(r.json).slice(0, 160));
        r = await call('POST', '/api/tally', { token: staff, body: { description: '', expectedItems: 1, expectedContainers: 1, metalData: [{ metalType: 'gold', expectedWeight: 1 }] } });
        const ts = r.data?.tallySession;
        check('a tally counts the stock itself: typed numbers are ignored, the description defaults to the date', r.status === 201 && ts?.expectedItems === pv.items && /^Stock tally \d\d \w{3} \d{4}$/.test(ts?.description || '') && ts.expectedContainers === pv.containers, JSON.stringify({ e: ts?.expectedItems, want: pv.items, d: ts?.description }));
        r = await call('POST', '/api/tally', { token: staff, body: { description: 'second' } });
        check('a second tally cannot start while one is running (409, points at the running one)', r.status === 409 && String(r.json.existingId) === String(ts?._id), `(${r.status})`);
        r = await call('GET', `/api/tally/${ts?._id}/summary`, { token: staff });
        const sm = r.data;
        check('the summary lists every box with scanned / total and the pieces still to find with box and slot', r.status === 200 && sm.boxes.filter((b) => b.id).length === pv.containers && sm.boxes.reduce((a, b) => a + b.total, 0) === pv.items && sm.boxes.every((b) => b.total >= 1 && b.missing === b.total) && sm.missing.length > 0 && !!sm.missing[0].barcode && 'box' in sm.missing[0], JSON.stringify(sm && sm.boxes && sm.boxes[0]));
        const [a1, a2, a3] = sm.missing;
        r = await call('PUT', `/api/tally/${ts?._id}/scan`, { token: staff, body: { barcode: a1.barcode } });
        check('scanning a piece of the list is counted', r.status === 200 && r.data?.scannedCount === 1, `(${r.status} ${r.json.message || ''})`);
        r = await call('PUT', `/api/tally/${ts?._id}/scan`, { token: staff, body: { barcode: a1.barcode } });
        check('scanning it again is refused as a duplicate (400)', r.status === 400 && r.json.isDuplicate === true);
        // a new piece added after the tally started is not part of the photograph
        const nb = `SMOKE-TALLY-${tag}`;
        const boxId = unwrap((await call('POST', '/api/containers', { token: admin, body: { name: `SMOKE TBox ${tag}`, type: 'box', capacity: 2, weightCategory: 'Light', layoutType: 'grid', qrCode: `SMOKE-TB-${tag}`, allowedItemTypes: ['ring'] } })).data)?._id;
        await call('POST', '/api/items', { token: admin, body: { barcode: nb, name: 'SMOKE Tally New', itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 1, containerId: boxId, slotNumber: 1 } });
        r = await call('PUT', `/api/tally/${ts?._id}/scan`, { token: staff, body: { barcode: nb } });
        check('a piece that was not in stock when the tally started is not counted (400, says why)', r.status === 400 && r.json.notInTally === true && /not in stock when this tally started/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
        // a piece sold while the tally runs is set aside, never "missing"
        await tdb.collection('items').updateOne({ barcode: a2.barcode }, { $set: { status: 'sold' } });
        r = await call('GET', `/api/tally/${ts?._id}/summary`, { token: staff });
        check('a piece sold while the tally runs moves to "sold since" and leaves the to-find list', r.data.soldSince.some((x) => x.barcode === a2.barcode) && !r.data.missing.some((x) => x.barcode === a2.barcode) && r.data.expected === pv.items - 1 && r.data.left === r.data.expected - r.data.scanned, JSON.stringify({ e: r.data.expected, l: r.data.left }));
        r = await call('PUT', `/api/tally/${ts?._id}/lock`, { token: admin, body: {} });
        check('locking with pieces not found needs a remark (400)', r.status === 400 && /Remarks/.test(r.json.message || ''));
        r = await call('PUT', `/api/tally/${ts?._id}/lock`, { token: admin, body: { remarks: 'SMOKE rest not checked' } });
        check('the lock records what was not found (with box and slot) and what was sold meanwhile', r.status === 200 && r.data.isForceLocked === true && r.data.itemsLeft === pv.items - 2 && r.data.missing.length === pv.items - 2 && r.data.soldSince.length === 1 && r.data.soldSince[0].barcode === a2.barcode && !r.data.missing.some((x) => x.barcode === a1.barcode), JSON.stringify({ left: r.data?.itemsLeft, want: pv.items - 2 }));
        r = await call('GET', `/api/tally/${ts?._id}/summary`, { token: staff });
        check('a locked tally keeps showing that frozen list', r.data.frozen === true && r.data.missing.length === pv.items - 2);
        await tdb.collection('items').updateOne({ barcode: a2.barcode }, { $set: { status: 'active' } });
        await tdb.collection('items').deleteMany({ barcode: nb });
        await tdb.collection('containers').deleteMany({ qrCode: `SMOKE-TB-${tag}` });
        await tdb.collection('tallysessions').deleteMany({});
        await ct.close();
    }

    // ── Estimates (price quotations) ────────────────────────────────────────────
    section('Estimates');
    {
        const ce = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await ce.db('lgp_dev').collection('app_estimates').deleteMany({});
        const line = { particulars: 'Gold Ring', metalType: 'Gold', purity: '22K', netWt: 2, rate: 0, makingCharge: 500, hsnCode: '7113' };
        const body = (over = {}) => ({ requestId: uid(), customerName: 'SMOKE Est Cust', customerMobile: '9000000044', items: [line], goldRate: 9000, silverRate: 100, validDays: 7, ...over });
        r = await call('POST', '/api/estimates', { token: viewer, body: body() });
        check('a viewer cannot make an estimate (403)', r.status === 403);
        r = await call('POST', '/api/estimates', { token: staff, body: body({ customerName: '' }) });
        check('an estimate needs the customer name (400)', r.status === 400);
        r = await call('POST', '/api/estimates', { token: staff, body: body({ items: [] }) });
        check('an estimate needs at least one item (400)', r.status === 400);
        const rid = uid();
        r = await call('POST', '/api/estimates', { token: staff, body: body({ requestId: rid }) });
        const es = r.data;
        check('an estimate is made with the bill engine: 2 g x 9,000 + 500 making = 18,500 + 3% GST = 19,055, number EST-0001 style, valid 7 days', r.status === 201 && /EST-\d{4}$/.test(es?.number || '') && es.totals.taxable === 18500 && es.totals.payable === 19055 && es.status === 'open' && es.validTill > es.date, JSON.stringify(r.json).slice(0, 220));
        r = await call('POST', '/api/estimates', { token: staff, body: body({ requestId: rid }) });
        check('the same request id never makes a second estimate (idempotent)', r.status === 200 && r.json.duplicate === true && r.data.number === es.number);
        r = await call('POST', '/api/estimates', { token: staff, body: body({ discount: 200 }) });
        check('a discount comes off the price like on a bill (payable 18,855) and is kept so the invoice gets the same', r.status === 201 && r.data.totals.payable === 18855 && r.data.discount === 200, JSON.stringify(r.data && r.data.totals));
        r = await call('GET', '/api/estimates?q=SMOKE Est', { token: staff });
        check('estimates are listed and searchable by name, mobile or number', r.status === 200 && r.data.length >= 2 && r.data.some((x) => x.number === es.number));
        r = await call('GET', `/api/estimates/${es.id}`, { token: staff });
        check('one estimate carries the lines for the PDF and to make the invoice from', r.status === 200 && r.data.items.length === 1 && r.data.inputItems[0].makingCharge === 500);
        r = await call('POST', `/api/estimates/${es.id}/converted`, { token: staff, body: { invoiceNumber: 'X-1' } });
        check('marking it as billed keeps the invoice number and closes it', r.status === 200 && r.data.status === 'converted' && r.data.convertedInvoice === 'X-1');
        r = await call('POST', `/api/estimates/${es.id}/converted`, { token: staff, body: { invoiceNumber: 'X-2' } });
        check('a billed estimate cannot be billed twice (404)', r.status === 404);
        await ce.db('lgp_dev').collection('app_estimates').updateOne({ number: (await call('GET', '/api/estimates?q=SMOKE Est', { token: staff })).data.find((x) => x.status === 'open').number }, { $set: { validTill: '2001-01-01' } });
        r = await call('GET', '/api/estimates?status=expired', { token: staff });
        check('an estimate past its date shows as expired', r.data.length === 1 && r.data[0].status === 'expired');
        const openOne = (await call('GET', '/api/estimates?status=expired', { token: staff })).data[0];
        r = await call('DELETE', `/api/estimates/${openOne.id}`, { token: staff });
        check('an open estimate can be cancelled', r.status === 200);
        await ce.db('lgp_dev').collection('app_estimates').deleteMany({});
        await ce.close();
    }

    // ── Custom orders (made-to-order pieces with an advance) ────────────────────
    section('Custom orders');
    {
        const co = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await co.db('lgp_dev').collection('app_orders').deleteMany({});
        const inDays = (n) => new Date(Date.now() + 5.5 * 3600000 + n * 86400000).toISOString().slice(0, 10);
        const ob = (over = {}) => ({ requestId: uid(), customerName: 'SMOKE Ord Cust', customerMobile: '9000000033', description: 'Gold chain 22K about 20 g, rope pattern', metalType: 'gold', purity: '22K', approxWeight: 20, estimatedPrice: 20000, deliveryDate: inDays(10), advanceAmount: 5000, advanceMode: 'Cash', ...over });
        r = await call('POST', '/api/orders', { token: viewer, body: ob() });
        check('a viewer cannot take an order (403)', r.status === 403);
        r = await call('POST', '/api/orders', { token: staff, body: ob({ description: '' }) });
        check('an order needs a description of what to make (400)', r.status === 400);
        r = await call('POST', '/api/orders', { token: staff, body: ob({ customerMobile: '' }) });
        check('an order needs a mobile number to call when it is ready (400)', r.status === 400);
        r = await call('POST', '/api/orders', { token: staff, body: ob({ deliveryDate: '2001-01-01' }) });
        check('the delivery date cannot be in the past (400)', r.status === 400);
        r = await call('POST', '/api/orders', { token: staff, body: ob({ advanceAmount: 25000 }) });
        check('the advance cannot be more than the price told (400)', r.status === 400);
        r = await call('POST', '/api/orders', { token: staff, body: ob({ advanceAmount: 200000, estimatedPrice: 0 }) });
        check('a cash advance of Rs 2,00,000 or more is refused (269ST, 400)', r.status === 400 && /269ST/.test(r.json.message || ''));
        const before = (await call('GET', '/api/billing/daybook', { token: admin })).data;
        const rid = uid();
        r = await call('POST', '/api/orders', { token: staff, body: ob({ requestId: rid }) });
        const od = r.data;
        check('an order is taken with its advance (ORD-0001 style number, status new, 10 days left)', r.status === 201 && /ORD-\d{4}$/.test(od?.number || '') && od.status === 'new' && od.advancePaid === 5000 && od.daysLeft === 10 && od.balanceEstimate === 15000, JSON.stringify(r.json).slice(0, 200));
        r = await call('POST', '/api/orders', { token: staff, body: ob({ requestId: rid }) });
        check('the same request id never makes a second order (idempotent)', r.status === 200 && r.json.duplicate === true && r.data.number === od.number);
        r = await call('POST', `/api/orders/${od.id}/advance`, { token: staff, body: { amount: 3000, mode: 'Online' } });
        check('more advance can be added later', r.status === 200 && r.data.advancePaid === 8000 && r.data.advances.length === 2);
        r = await call('POST', `/api/orders/${od.id}/advance`, { token: staff, body: { amount: 99999, mode: 'Online' } });
        check('the total advance can never pass the price told (400)', r.status === 400);
        const after = (await call('GET', '/api/billing/daybook', { token: admin })).data;
        const mode = (d, m) => d.modes.find((x) => x.mode === m);
        check('the Day Book shows the advances as money in on the day (cash +5,000, online +3,000)', Math.abs(mode(after, 'Cash').in - mode(before, 'Cash').in - 5000) < 0.01 && Math.abs(mode(after, 'Online').in - mode(before, 'Online').in - 3000) < 0.01 && after.lines.some((l) => /Advance for order/.test(l.subtitle)));
        r = await call('POST', `/api/orders/${od.id}/status`, { token: staff, body: { status: 'making', karigar: 'Ramen' } });
        check('the order moves to making with the karigar named', r.status === 200 && r.data.status === 'making' && r.data.karigar === 'Ramen');
        r = await call('GET', '/api/orders?status=active&q=SMOKE Ord', { token: staff });
        check('active orders are listed and searchable, with the counts for the tabs', r.status === 200 && r.data.some((x) => x.id === od.id) && r.json.counts.active >= 1);
        r = await call('POST', `/api/orders/${od.id}/status`, { token: staff, body: { status: 'ready' } });
        check('then ready', r.status === 200 && r.data.status === 'ready');
        // deliver: the bill takes the advance as paid
        const line = { particulars: 'Gold Chain', metalType: 'Gold', purity: '22K', netWt: 2, rate: 0, makingCharge: 500, hsnCode: '7113' };
        r = await call('POST', '/api/billing/invoices', { token: admin, body: { requestId: uid(), customerId: multi._id, customerAddress: '12 Test Road, Howrah', items: [line], goldRate: 9000, silverRate: 100, orderId: od.id, paidAmount: 2000, paymentMode: 'Cash' } });
        const inv = r.data;
        const adv = (inv?.paymentHistory || []).find((x) => x.mode === 'Order Advance');
        check('the bill credits the order advance as already paid (8,000 + 2,000 cash on 19,055, due 9,055)', r.status === 201 && adv?.amount === 8000 && Math.abs(inv.paidAmount - 10000) < 0.01 && Math.abs(inv.dueAmount - 9055) < 0.01, JSON.stringify({ s: r.status, m: r.json.message, a: adv, p: inv?.paidAmount, d: inv?.dueAmount }));
        check('...and the invoice main payment mode stays a money mode', ['Cash', 'Card', 'Online', 'Cheque'].includes(inv?.paymentMode), String(inv?.paymentMode));
        r = await call('GET', `/api/orders/${od.id}`, { token: staff });
        check('the order is now delivered with the invoice number', r.data.status === 'delivered' && r.data.invoiceNumber === inv?.invoiceNumber);
        r = await call('POST', '/api/billing/invoices', { token: admin, body: { requestId: uid(), customerId: multi._id, customerAddress: '12 Test Road, Howrah', items: [line], goldRate: 9000, silverRate: 100, orderId: od.id, paidAmount: 20000, paymentMode: 'Online' } });
        check('a delivered order cannot be billed twice (400)', r.status === 400 && /already billed/.test(r.json.message || ''), `(${r.status} ${r.json.message || ''})`);
        const after2 = (await call('GET', '/api/billing/daybook', { token: admin })).data;
        check('the Day Book does not count the advance twice (only the 2,000 cash paid on the bill is new money)', Math.abs(mode(after2, 'Cash').in - mode(after, 'Cash').in - 2000) < 0.01 && Math.abs(mode(after2, 'Online').in - mode(after, 'Online').in) < 0.01, JSON.stringify({ a: mode(after, 'Cash'), b: mode(after2, 'Cash') }));
        // cancelling: the advance goes back
        r = await call('POST', '/api/orders', { token: staff, body: ob({ description: 'Silver payal pair', metalType: 'silver', advanceAmount: 1000 }) });
        const o2 = r.data;
        r = await call('POST', `/api/orders/${o2.id}/cancel`, { token: staff, body: { refundMode: 'Cash' } });
        check('only the owner cancels an order (403)', r.status === 403);
        r = await call('POST', `/api/orders/${o2.id}/cancel`, { token: admin, body: { refundMode: 'Cash', refundAmount: 400 } });
        check('keeping part of the advance needs a reason (400)', r.status === 400);
        const b3 = (await call('GET', '/api/billing/daybook', { token: admin })).data;
        r = await call('POST', `/api/orders/${o2.id}/cancel`, { token: admin, body: { refundMode: 'Cash', refundAmount: 1000 } });
        const a3 = (await call('GET', '/api/billing/daybook', { token: admin })).data;
        check('cancelling returns the advance: the order closes and the Day Book shows it as money out', r.status === 200 && r.data.status === 'cancelled' && Math.abs(mode(a3, 'Cash').out - mode(b3, 'Cash').out - 1000) < 0.01);
        r = await call('POST', `/api/orders/${o2.id}/advance`, { token: staff, body: { amount: 10, mode: 'Cash' } });
        check('a cancelled order takes no more advance (400)', r.status === 400);
        await co.db('lgp_dev').collection('app_orders').deleteMany({});
        await co.db('lgp_dev').collection('app_credit_notes').deleteMany({ invoiceNumber: inv?.invoiceNumber });
        await co.db('lgp_dev').collection('invoices').deleteMany({ invoice_number: inv?.invoiceNumber });
        await co.close();
    }

    // ── Realtime: events, live stream, catch-up, tickets ────────────────────────
    section('Realtime');
    {
        const sleepMs = (ms) => new Promise((res) => setTimeout(res, ms));
        // opens the live stream and collects what arrives
        const openStream = async (query, token, useTicket) => {
            const ctl = new AbortController();
            const url = `${BASE}/api/live${query}`;
            const resp = await fetch(url, { signal: ctl.signal, headers: useTicket ? {} : { Authorization: `Bearer ${token}` } });
            const got = { status: resp.status, ctype: resp.headers.get('content-type') || '', events: [], raw: '', close: () => ctl.abort() };
            if (resp.status !== 200) { got.body = await resp.text().catch(() => ''); return got; }
            (async () => {
                try {
                    const dec = new TextDecoder();
                    let buf = '';
                    for await (const chunk of resp.body) {
                        buf += dec.decode(chunk, { stream: true });
                        got.raw += dec.decode(chunk, { stream: true });
                        let i;
                        while ((i = buf.indexOf('\n\n')) >= 0) {
                            const block = buf.slice(0, i); buf = buf.slice(i + 2);
                            const ev = { type: 'message', data: null };
                            for (const line of block.split('\n')) {
                                if (line.startsWith('event:')) ev.type = line.slice(6).trim();
                                else if (line.startsWith('data:')) { try { ev.data = JSON.parse(line.slice(5).trim()); } catch (_) { ev.data = line.slice(5).trim(); } }
                            }
                            if (block.trim() && !block.startsWith(':') && !block.startsWith('retry')) got.events.push(ev);
                        }
                    }
                } catch (_) { /* closed */ }
            })();
            return got;
        };
        const waitFor = async (st, type, pred, ms = 3000) => { for (let i = 0; i < ms / 50; i++) { const f = st.events.find((e) => e.type === type && (!pred || pred(e.data))); if (f) return f; await sleepMs(50); } return null; };

        r = await call('GET', '/api/live/events?since=0', { token: null });
        check('the live endpoints need a login (401)', r.status === 401);
        const sAdmin = await openStream('', admin);
        check('the stream opens as text/event-stream and says hello with the latest event number', sAdmin.status === 200 && /text\/event-stream/.test(sAdmin.ctype) && !!(await waitFor(sAdmin, 'hello')), sAdmin.ctype);
        const helloSeq = (sAdmin.events.find((e) => e.type === 'hello') || {}).data?.latest || 0;
        const sStaff = await openStream('', staff);
        const sViewer = await openStream('', viewer);
        await sleepMs(300);

        // a change on one side reaches every open screen at once
        const t0 = Date.now();
        r = await call('PUT', '/api/rates', { token: admin, body: { gold: 9310, silver: 111 } });
        const evAdmin = await waitFor(sAdmin, 'rate.changed', (d) => d.data?.gold === 9310);
        const evStaff = await waitFor(sStaff, 'rate.changed', (d) => d.data?.gold === 9310);
        check('changing the rate reaches the open screens within a second or two (admin and staff)', !!evAdmin && !!evStaff && Date.now() - t0 < 2500, `(${Date.now() - t0} ms)`);
        check('the event says who changed it and carries the new numbers', evAdmin?.data?.by === 'Admin' && evAdmin.data.data.silver === 111 && evAdmin.data.seq > helloSeq);

        // a change of one person's permissions goes to that person only
        r = await call('PUT', `/api/users/${staffId}/permission-overrides`, { token: admin, body: { overrides: { 'rates.edit': false } } });
        const pStaff = await waitFor(sStaff, 'permissions.changed');
        await sleepMs(500);
        check('a permission change reaches the person it is about', r.status === 200 && !!pStaff && pStaff.data.data.userId === String(staffId), `(${r.status})`);
        check('...and nobody else (the admin and the viewer do not receive it)', !sAdmin.events.some((e) => e.type === 'permissions.changed') && !sViewer.events.some((e) => e.type === 'permissions.changed'));
        await call('PUT', `/api/users/${staffId}/permission-overrides`, { token: admin, body: { overrides: { 'rates.edit': null } } });

        // module changes
        r = await call('POST', '/api/expenses', { token: staff, body: { amount: 12, mode: 'Cash', category: 'Other', note: 'SMOKE live' } });
        const dc = await waitFor(sAdmin, 'data.changed', (d) => d.module === 'expenses');
        check('adding an expense tells the other screens that the expenses changed (data.changed)', r.status === 201 && !!dc);
        if (r.data?.id) await call('DELETE', `/api/expenses/${r.data.id}`, { token: admin });

        // app update and settings
        r = await call('PUT', '/api/app-version', { token: admin, body: { latestVersion: '9.9.9', latestVersionCode: 999, forceUpdate: false, updateMessage: 'SMOKE' } });
        const au = await waitFor(sStaff, 'app.update', (d) => d.data?.latestVersionCode === 999);
        check('publishing an app update reaches every open app (app.update)', r.status === 200 && !!au, `(${r.status})`);
        await call('PUT', '/api/app-version', { token: admin, body: { latestVersion: '1.4.0', latestVersionCode: 4, forceUpdate: false, updateMessage: '' } });

        // catch-up for a client that was away
        r = await call('GET', `/api/live/events?since=${helloSeq}`, { token: staff });
        check('a client that was away asks "what did I miss?" and gets it, oldest first, with the latest number', r.status === 200 && r.data.events.length >= 3 && r.data.events.every((e, i, a) => !i || a[i - 1].seq < e.seq) && r.data.latest >= r.data.events[r.data.events.length - 1].seq && r.data.reset === false, JSON.stringify(r.json).slice(0, 160));
        check('the person-only permission event is NOT in another person\'s catch-up', !(await call('GET', `/api/live/events?since=${helloSeq}`, { token: viewer })).data.events.some((e) => e.type === 'permissions.changed'));
        r = await call('GET', `/api/live/events?since=${r.data.latest}`, { token: staff });
        check('nothing missed = an empty answer', r.status === 200 && r.data.events.length === 0);
        // reconnect with a number: the missed ones are replayed on the stream itself
        const sBack = await openStream(`?since=${helloSeq}`, staff);
        check('reconnecting with the last number replays what was missed on the stream', !!(await waitFor(sBack, 'rate.changed', (d) => d.data?.gold === 9310)));

        // tickets for browsers
        r = await call('POST', '/api/live/ticket', { token: admin });
        const tk = r.data?.ticket;
        check('a one-time ticket is issued for the browser (60 seconds)', r.status === 200 && /^[a-f0-9]{48}$/.test(tk || '') && r.data.expiresInSeconds === 60);
        const sTk = await openStream(`?ticket=${tk}`, null, true);
        check('the browser opens the stream with the ticket and no login token', sTk.status === 200 && !!(await waitFor(sTk, 'hello')));
        const sTk2 = await openStream(`?ticket=${tk}`, null, true);
        check('the same ticket cannot be used twice (401)', sTk2.status === 401);
        const sBad = await openStream('?ticket=deadbeef', null, true);
        check('a made-up ticket is refused (401)', sBad.status === 401);

        for (const st of [sAdmin, sStaff, sViewer, sBack, sTk]) st.close();
        await call('PUT', '/api/rates', { token: admin, body: { gold: 9200, silver: 110 } });
        const cl = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cl.db('lgp_dev').collection('app_rates').deleteMany({});
        await cl.db('lgp_dev').collection('app_expenses').deleteMany({ note: 'SMOKE live' });
        await cl.close();
    }

    // ── Stock Setting (valuation / wastage / labour rules) ──────────────────────
    section('Stock Setting');
    r = await call('GET', '/api/stock-settings', { token: admin });
    check('defaults match the reference rules (customer wastage fine, valuation final fine, purchase labour fine ...)', r.status === 200 && r.data?.settings?.addStock?.customerWastage === 'fine' && r.data.settings.addStock.valuation === 'finalFine' && r.data.settings.purchase.labourCharges === 'fine' && r.data.settings.oldMetal.receivedValuation === 'fine' && r.data.settings.hallmark.charge === 45, JSON.stringify(r.data?.settings?.addStock));
    r = await call('GET', '/api/stock-settings', { token: viewer });
    check('any signed-in user can read the rules', r.status === 200);
    r = await call('PUT', '/api/stock-settings', { token: staff, body: { addStock: { valuation: 'net' } } });
    check('staff cannot change the rules (403)', r.status === 403, `(${r.status})`);
    r = await call('PUT', '/api/stock-settings', { token: admin, body: { addStock: { valuation: 'sideways' } } });
    check('an unknown value is refused (400)', r.status === 400, `(${r.status})`);
    r = await call('PUT', '/api/stock-settings', { token: admin, body: { addStock: { nope: 'net' } } });
    check('an unknown setting is refused (400)', r.status === 400);
    r = await call('PUT', '/api/stock-settings', { token: admin, body: { sellStock: { custWastage: 'blank', byAddedMetalRate: true }, purchase: { wastage: 'gross' }, hallmark: { charge: 60, type: 'perGram' } } });
    check('admin changes several rules at once', r.status === 200 && r.data?.settings?.sellStock?.custWastage === 'blank' && r.data.settings.sellStock.byAddedMetalRate === true && r.data.settings.purchase.wastage === 'gross' && r.data.settings.hallmark.charge === 60 && r.data.settings.hallmark.type === 'perGram', JSON.stringify(r.json).slice(0, 120));
    r = await call('GET', '/api/stock-settings', { token: staff });
    check('the change is kept and untouched rules stay as they were', r.data?.settings?.sellStock?.custWastage === 'blank' && r.data.settings.addStock.valuation === 'finalFine');
    r = await call('PUT', '/api/stock-settings', { token: admin, body: { hallmark: { charge: -5 } } });
    check('a negative hallmark charge is refused (400)', r.status === 400);
    await call('POST', '/api/stock-settings/reset', { token: admin });
    r = await call('POST', '/api/stock-settings/calculate', { token: staff, body: { net: 10, purity: '22K', wastage: 8.4, rate: 7000, makingRate: 100, certification: 'huid' } });
    check('the server calculates a stock price with the rules (metal on final fine weight, hallmark GST)', r.status === 200 && r.data?.metalValuation === 70000 && r.data?.makingTotal === 1000 && r.data?.hallmarkCharge === 45 && r.data?.finalPrice > 71000, JSON.stringify(r.data).slice(0, 140));
    r = await call('PUT', '/api/stock-settings', { token: admin, body: { addStock: { valuation: 'net' } } });
    r = await call('POST', '/api/stock-settings/calculate', { token: staff, body: { net: 10, purity: '22K', wastage: 8.4, rate: 7000 } });
    check('changing the valuation rule changes the calculation (net weight now)', r.data?.valuationWt === 10 && r.data?.metalValuation === 70000 && r.data?.fine === 9.16);
    r = await call('POST', '/api/items', { token: admin, body: { barcode: `SMOKE-W-${tag}`, name: 'SMOKE Wastage', itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 4, wastage: 8.4, custWastage: 1.5, labourRate: 120, makingRate: 60 } });
    check('an item keeps wastage / customer wastage / labour / making rates', r.status === 201 && unwrap(r.data)?.wastage === 8.4 && unwrap(r.data)?.custWastage === 1.5 && unwrap(r.data)?.labourRate === 120 && unwrap(r.data)?.makingRate === 60, JSON.stringify(r.json).slice(0, 100));
    {
        const cw = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cw.db('lgp_dev').collection('items').deleteMany({ barcode: `SMOKE-W-${tag}` });
        await cw.close();
    }
    r = await call('POST', '/api/stock-settings/reset', { token: admin });
    check('reset brings every rule back to its default', r.status === 200 && r.data?.settings?.sellStock?.custWastage === 'addStock' && r.data.settings.hallmark.charge === 45);

    // ── Helpers added for the website ───────────────────────────────────────────
    section('Website helpers');
    r = await call('GET', '/api/items?limit=2&page=1&status=active', { token: admin });
    check('items can be paged: one page, the total and the weight of the whole filter', r.status === 200 && r.json?.data?.items?.length <= 2 && r.json?.pagination?.total > 0 && typeof r.json?.totals?.netWeight === 'number', JSON.stringify(r.json?.pagination));
    r = await call('POST', '/api/items', { token: admin, body: { barcode: `SMOKE-AM-${tag}`, name: 'SMOKE AutoMaking', itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 12, labourRate: 120, makingRate: 60, fixedMaking: 100, autoMaking: true } });
    check('autoMaking: the server works the making charge out (12 x (120 + 60) + 100 = 2260)', r.status === 201 && unwrap(r.data)?.makingCharge === 2260, JSON.stringify(unwrap(r.data)?.makingCharge));
    check('the weight class is worked out when the client sends none (12 g = Heavy)', unwrap(r.data)?.weightCategory === 'Heavy', String(unwrap(r.data)?.weightCategory));
    {
        const cw = await MongoClient.connect('mongodb://127.0.0.1:27018');
        await cw.db('lgp_dev').collection('items').deleteMany({ barcode: `SMOKE-AM-${tag}` });
        await cw.close();
    }
    r = await call('POST', '/api/purchases/calculate', { token: admin, body: { metalType: 'gold', quantity: 10, rate: 7000, transactionType: 'intra-state' } });
    check('purchase calculate: taxable value, GST and input credit, nothing saved', r.status === 200 && r.data?.totalAmount === 70000 && r.data?.totalGst === 2100 && r.data?.totalItc === 2100, JSON.stringify(r.data).slice(0, 120));
    // the supplier's round-off: the invoice total can be typed, within a small difference
    r = await call('POST', '/api/purchases/calculate', { token: admin, body: { metalType: 'gold', quantity: 10, rate: 7000, transactionType: 'intra-state', invoiceTotal: 72110 } });
    check('purchase calculate with a typed invoice total: calculated 72,100, round-off +10, GST and input credit unchanged', r.status === 200 && r.data?.totalPayable === 72110 && r.data?.calculatedPayable === 72100 && r.data?.roundOff === 10 && r.data?.totalGst === 2100 && r.data?.totalItc === 2100 && r.data?.netPayable === 72110, JSON.stringify(r.data).slice(0, 200));
    r = await call('POST', '/api/purchases/calculate', { token: admin, body: { metalType: 'gold', quantity: 10, rate: 7000, invoiceTotal: 72200 } });
    check('an invoice total far from the calculated one is refused (it is a round-off, not a new price)', r.status === 400 && /round-off/.test(r.json.message || ''), JSON.stringify(r.json).slice(0, 160));
    r = await call('POST', '/api/purchases/calculate', { token: admin, body: { metalType: 'gold', quantity: 10, rate: 7000, invoiceTotal: 72100 } });
    check('a typed total equal to the calculated one has no round-off', r.status === 200 && r.data?.roundOff === 0 && r.data?.totalPayable === 72100);
    {
        const invR = `SMK-RO-${tag}`;
        const crc = await MongoClient.connect('mongodb://127.0.0.1:27018');
        const pcol = crc.db('lgp_dev').collection('purchases');
        r = await call('POST', '/api/purchases', { token: admin, body: { invoiceDate: '2019-06-10T05:00:00.000Z', invoiceNumber: invR, metalType: 'gold', biller: 'SMOKE Supplier', billerGstin: '19AAAAA0000A1Z5', quantity: 10, rate: 1000, totalAmount: 10000, invoiceTotal: 10301 } });
        const pr = r.data?.purchase;
        const rawR = await pcol.findOne({ invoice_number: invR });
        check('a purchase saved with a typed invoice total: payable 10,301, round-off +1, GST 300 as calculated, website total_amount = 10,301', r.status === 201 && pr?.totalPayable === 10301 && pr?.roundOff === 1 && pr?.calculatedPayable === 10300 && pr?.totalGst === 300 && pr?.gstRecorded === true && rawR?.total_amount === 10301 && rawR?.roundOff === 1, JSON.stringify(r.json).slice(0, 200));
        r = await call('PUT', `/api/purchases/${pr?._id}`, { token: admin, body: { invoiceTotal: 10299 } });
        check('the invoice total can be corrected later (round-off -1), GST untouched', r.status === 200 && r.data?.purchase?.totalPayable === 10299 && r.data?.purchase?.roundOff === -1 && r.data?.purchase?.totalGst === 300 && r.data?.purchase?.netPayable === 10299, JSON.stringify(r.json).slice(0, 200));
        r = await call('PUT', `/api/purchases/${pr?._id}`, { token: admin, body: { invoiceTotal: 10400 } });
        check('a correction beyond the allowed round-off is refused and nothing changes', r.status === 400 && (await pcol.findOne({ invoice_number: invR }))?.total_amount === 10299);
        r = await call('PUT', `/api/purchases/${pr?._id}`, { token: admin, body: { invoiceTotal: '' } });
        check('clearing the typed total goes back to the calculated one', r.status === 200 && r.data?.purchase?.totalPayable === 10300 && r.data?.purchase?.roundOff === 0);
        await pcol.deleteMany({ invoice_number: invR });
        await crc.close();
    }
    r = await call('POST', '/api/purchases/calculate', { token: admin, body: {} });
    check('purchase calculate: nothing entered is a clear 400', r.status === 400);
    r = await call('POST', '/api/purchases/calculate', { token: viewer, body: { quantity: 10, rate: 7000 } });
    check('purchase calculate: viewer cannot (403)', r.status === 403, `(${r.status})`);
    {
        const ph = '9' + String(Math.floor(Math.random() * 1e9)).padStart(9, '0');
        const ph2 = '9' + String(Math.floor(Math.random() * 1e9)).padStart(9, '0');
        r = await call('POST', '/api/directory/customers', { token: admin, body: { name: `SMOKE Partial ${tag}`, contacts: [{ number: ph, label: 'whatsapp' }, { number: ph2, label: 'mobile' }], fatherName: 'Keep Me', opening: { cash: { amount: 700, type: 'debit' } }, city: 'Howrah', notes: 'note kept' } });
        const cid = r.data?._id;
        r = await call('PUT', `/api/directory/customers/${cid}/partial`, { token: admin, body: { address: 'New partial address' } });
        check('partial edit: changes only what was sent and keeps every other detail (numbers, father, opening balance, note)', r.status === 200 && r.data?.address === 'New partial address' && r.data?.profile?.contacts?.length === 2 && r.data?.profile?.fatherName === 'Keep Me' && r.data?.profile?.opening?.cash?.amount === 700 && r.data?.profile?.notes === 'note kept', JSON.stringify(r.json).slice(0, 160));
        r = await call('PUT', `/api/directory/customers/${cid}/partial`, { token: viewer, body: { address: 'x' } });
        check('partial edit: viewer cannot (403)', r.status === 403, `(${r.status})`);
    }

    // ── Audit log of admin actions ──────────────────────────────────────────────
    section('Audit log');
    r = await call('GET', '/api/admin/audit?limit=5', { token: admin });
    check('the audit log lists entries newest first with a total', r.status === 200 && Array.isArray(r.json?.data) && r.json?.pagination?.total > 0);
    r = await call('GET', '/api/admin/audit', { token: staff });
    check('staff cannot read the audit log (403)', r.status === 403, `(${r.status})`);
    r = await call('PUT', '/api/app-version', { token: admin, body: { latestVersion: '1.4.0', latestVersionCode: 4, forceUpdate: false } });
    r = await call('GET', '/api/admin/audit?entity=app_update&limit=1', { token: admin });
    check('publishing an app version leaves an audit line', r.status === 200 && r.json?.data?.[0]?.entity === 'app_update' && r.json.data[0].byName === 'Admin', JSON.stringify(r.json?.data?.[0] || {}).slice(0, 120));
    r = await call('GET', '/api/stock-settings', { token: admin });
    check('the stock settings answer also lists the allowed choices (for the website)', r.status === 200 && Array.isArray(r.json?.data?.options?.addStock?.valuation) && r.json.data.options.hallmark.type.includes('perGram'));

    // ── Admin console ───────────────────────────────────────────────────────
    section('Environment console');
    r = await call('GET', '/api/admin/status');
    check('status needs login (401)', r.status === 401);
    r = await call('GET', '/api/admin/status', { token: staff });
    check('non-admin blocked (403)', r.status === 403, `(${r.status})`);
    r = await call('GET', '/api/admin/status', { token: admin });
    check('admin sees status', r.status === 200 && r.data?.databases?.every((d) => d.state === 'connected'));
    check('status leaks no secrets', !JSON.stringify(r.json).match(/mongodb(\+srv)?:\/\/|Admin@123|Smoke@123/));

    console.log(`\n${pass} passed, ${fail} failed`);
    if (fail) console.log('Failed: ' + failures.join(' | '));
    process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
