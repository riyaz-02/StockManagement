/**
 * local-db.js — a throwaway LOCAL MongoDB for development/testing.
 *
 * Runs a real mongod on 127.0.0.1:27018 with data kept in backend/.localdb
 * (gitignored), so nothing here can touch the production Atlas clusters.
 * On first run it seeds FAKE data shaped like the LGP admin collections
 * (customers, users) so the User Directory can be exercised end to end.
 *
 *   node scripts/local-db.js            # start (keep running)
 *   node scripts/local-db.js --reset    # wipe the local data and re-seed
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { MongoMemoryServer } = require('mongodb-memory-server');
const { MongoClient } = require('mongodb');

const PORT = 27018;
const DB_PATH = path.join(__dirname, '..', '.localdb');
const LGP_DB = 'lgp_dev';

const FIRST = ['Rahul', 'Priya', 'Amit', 'Sunita', 'Debasish', 'Mousumi', 'Sanjay', 'Rina', 'Kabir', 'Anita',
    'Subrata', 'Papiya', 'Tapan', 'Kajal', 'Ranjit', 'Shilpa', 'Biswajit', 'Nandini', 'Partha', 'Sumana'];
const LAST = ['Das', 'Ghosh', 'Sarkar', 'Mondal', 'Roy', 'Paul', 'Saha', 'Dutta'];
const TOWNS = ['Humbirpara', 'Howrah', 'Uluberia', 'Kolkata', 'Bagnan'];

async function seedLgp(uri) {
    const client = await MongoClient.connect(uri);
    const db = client.db(LGP_DB);
    if ((await db.collection('customers').estimatedDocumentCount()) > 0) {
        await client.close();
        return false;
    }
    const now = new Date();
    const customers = Array.from({ length: 60 }, (_, i) => {
        const n = i + 1;
        const c = {
            customer_name: `TEST ${FIRST[i % FIRST.length]} ${LAST[i % LAST.length]}`,
            customer_name_bengali: '',
            address: `${n} Test Road, ${TOWNS[i % TOWNS.length]}`,
            address_bengali: '',
            // Fake numbers only (900000xxxx) — cannot belong to a real customer.
            whatsapp_no: `90000${String(n).padStart(5, '0')}`,
            mobile_no: i % 10 === 0 ? `91000${String(n).padStart(5, '0')}` : '',
            notification_type: i % 7 === 0 ? 'none' : 'all',
            created_by: 'seed', created_by_name: 'Seed',
            created_at: new Date(now - i * 86400000), updated_at: now,
            sl_no: n,
        };
        if (i % 12 === 5) c.is_deleted = true; // soft-deleted: must be hidden by the app
        return c;
    });
    await db.collection('customers').insertMany(customers);

    // Fake login accounts. The "password" is a dummy string — the point is to
    // prove the API never returns these fields.
    await db.collection('users').insertMany([
        ['test_admin', 'Test Admin', 'admin'], ['test_manager', 'Test Manager', 'manager'],
        ['test_staff1', 'Test Staff One', 'staff'], ['test_staff2', 'Test Staff Two', 'staff'],
    ].map(([username, full_name, role], i) => ({
        username, email: `${username}@example.test`, password: 'SHOULD-NEVER-LEAK', full_name, role,
        contact: `92000${String(i + 1).padStart(5, '0')}`, address: 'Test Address', profile_image: '',
        created_at: now, is_active: true, status: 'active', remember_token: 'SHOULD-NEVER-LEAK',
    })));
    await client.close();
    return true;
}

(async () => {
    if (process.argv.includes('--reset')) fs.rmSync(DB_PATH, { recursive: true, force: true });
    fs.mkdirSync(DB_PATH, { recursive: true });

    const mongod = await MongoMemoryServer.create({
        instance: { port: PORT, ip: '127.0.0.1', dbPath: DB_PATH, storageEngine: 'wiredTiger' },
    });
    const base = mongod.getUri();
    const seeded = await seedLgp(base);
    await require('./seed-legacy-invoices').seedLegacyInvoices(base, LGP_DB).catch((e) => console.error('legacy invoice seed skipped:', e.message));
    console.log(`Local MongoDB ready on ${base}  (data: ${DB_PATH})`);
    console.log(seeded ? 'Seeded fake LGP data: 60 customers (5 soft-deleted), 4 staff logins.' : 'Existing local data kept.');

    const stop = async () => { await mongod.stop({ doCleanup: false }); process.exit(0); };
    process.on('SIGINT', stop);
    process.on('SIGTERM', stop);
})().catch((e) => { console.error('local-db failed:', e); process.exit(1); });
