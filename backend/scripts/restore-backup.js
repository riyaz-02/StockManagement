/**
 * restore-backup.js - put a backup made on the website's "Data backup" page back into a MongoDB database, without needing
 * the MongoDB Database Tools. It reads the unzipped folder (the `dump/` part) and
 *   - shows a PLAN by default and changes nothing;
 *   - with --apply, ADDS what is missing: a document whose _id already exists is left alone (nothing is ever overwritten or dropped);
 *   - recreates collection options, views and indexes that are missing.
 *
 *   node scripts/restore-backup.js <unzipped folder> <target connection string> [--apply] [--only db[.collection]] [--into newDbName]
 *
 * --into renames the database while restoring (only valid when the folder holds one database, or together with --only db).
 * Restoring into a copy first (--into shopmanage_check) and comparing is the careful way to test a backup.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { MongoClient, BSON } = require('mongoose').mongo;

const { EJSON } = BSON;
const BATCH = 500;

/** Walk the documents of a .bson file without loading it all: [int32 length][document] repeated. */
async function* bsonDocs(file) {
    let carry = Buffer.alloc(0);
    for await (const chunk of fs.createReadStream(file, { highWaterMark: 1 << 20 })) {
        carry = carry.length ? Buffer.concat([carry, chunk]) : chunk;
        let at = 0;
        while (carry.length - at >= 4) {
            const len = carry.readInt32LE(at);
            if (len < 5) throw new Error(`${path.basename(file)} is damaged (a document claims a length of ${len})`);
            if (carry.length - at < len) break;
            yield carry.subarray(at, at + len);
            at += len;
        }
        carry = carry.subarray(at);
    }
    if (carry.length) throw new Error(`${path.basename(file)} ends in the middle of a document: the file is incomplete`);
}

const countDocs = async (file) => { let n = 0; for await (const d of bsonDocs(file)) { n += d ? 1 : 0; } return n; };

function findDump(folder) {
    const direct = path.join(folder, 'dump');
    if (fs.existsSync(direct)) return direct;
    const inner = fs.readdirSync(folder, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => path.join(folder, d.name, 'dump')).find((p) => fs.existsSync(p));
    if (inner) return inner;
    if (fs.readdirSync(folder, { withFileTypes: true }).some((d) => d.isDirectory() && fs.readdirSync(path.join(folder, d.name)).some((f) => f.endsWith('.bson') || f.endsWith('.metadata.json')))) return folder;
    throw new Error('No "dump" folder found in that folder. Give the folder you got by unzipping the backup.');
}

const readMeta = (file) => (fs.existsSync(file) ? EJSON.parse(fs.readFileSync(file, 'utf8'), { relaxed: false }) : { options: {}, indexes: [] });

/** @returns {Promise<{plan:Array,applied:boolean}>} one row per collection: what is in the file, what the target already has, what was added */
async function restoreFolder({ folder, uri, apply = false, only = '', into = '', log = () => {} }) {
    const dump = findDump(folder);
    const [onlyDb, onlyColl] = only ? only.split('.') : ['', ''];
    const dbs = fs.readdirSync(dump, { withFileTypes: true }).filter((d) => d.isDirectory() && (!onlyDb || d.name === onlyDb)).map((d) => d.name);
    if (!dbs.length) throw new Error('Nothing to restore (no such database in the backup).');
    if (into && dbs.length > 1) throw new Error('--into needs exactly one database: add --only <database>.');

    const client = new MongoClient(uri, { serverSelectionTimeoutMS: 15000, appName: 'lgp-restore' });
    await client.connect();
    const plan = [];
    try {
        for (const dbName of dbs) {
            const target = client.db(into || dbName);
            const existing = new Set((await target.listCollections().toArray()).map((c) => c.name));
            const names = [...new Set(fs.readdirSync(path.join(dump, dbName)).filter((f) => f.endsWith('.bson') || f.endsWith('.metadata.json')).map((f) => f.replace(/\.(bson|metadata\.json)$/, '')))]
                .filter((n) => !onlyColl || n === onlyColl).sort();
            for (const name of names) {
                const bsonFile = path.join(dump, dbName, `${name}.bson`);
                const meta = readMeta(path.join(dump, dbName, `${name}.metadata.json`));
                const isView = !!(meta.options && meta.options.viewOn);
                const row = { db: into || dbName, collection: name, kind: isView ? 'view' : 'collection', inBackup: isView ? null : await countDocs(bsonFile), alreadyThere: 0, added: 0, skippedExisting: 0, indexesAdded: 0 };
                if (existing.has(name) && !isView) row.alreadyThere = await target.collection(name).estimatedDocumentCount();
                plan.push(row);
                if (!apply) continue;

                if (!existing.has(name)) await target.createCollection(name, meta.options || {});
                if (isView) continue;
                const col = target.collection(name);
                let batch = [];
                const flush = async () => {
                    if (!batch.length) return;
                    try {
                        const r = await col.insertMany(batch, { ordered: false });
                        row.added += r.insertedCount;
                    } catch (e) {
                        const errs = [].concat(e.writeErrors || []);
                        const dup = errs.filter((w) => w.code === 11000).length;
                        const other = errs.length - dup;
                        if (other > 0 || !e.result) throw e;
                        row.added += (e.result.insertedCount || 0);
                        row.skippedExisting += dup;
                    }
                    batch = [];
                };
                for await (const buf of bsonDocs(bsonFile)) {
                    batch.push(BSON.deserialize(buf, { promoteValues: false, promoteBuffers: false, promoteLongs: false }));
                    if (batch.length >= BATCH) await flush();
                }
                await flush();
                const have = new Set((await col.indexes().catch(() => [])).map((i) => i.name));
                for (const ix of (meta.indexes || []).filter((i) => i.name !== '_id_' && !have.has(i.name))) {
                    const { key, name: ixName, v, ns, ...opts } = ix;
                    await col.createIndex(key, { name: ixName, ...opts });
                    row.indexesAdded += 1;
                }
                log(`  ${row.db}.${name}: +${row.added} documents (${row.skippedExisting} already there)`);
            }
        }
    } finally {
        await client.close().catch(() => {});
    }
    return { plan, applied: apply };
}

module.exports = { restoreFolder, bsonDocs };

if (require.main === module) {
    (async () => {
        const args = process.argv.slice(2);
        const flag = (n) => { const i = args.indexOf(n); return i >= 0 ? args.splice(i, 2)[1] : ''; };
        const apply = args.includes('--apply');
        if (apply) args.splice(args.indexOf('--apply'), 1);
        const only = flag('--only');
        const into = flag('--into');
        const [folder, uri] = args;
        if (!folder || !uri) {
            console.log('Usage: node scripts/restore-backup.js <unzipped folder> <target connection string> [--apply] [--only db[.collection]] [--into newDbName]');
            process.exit(1);
        }
        const host = uri.replace(/^mongodb(\+srv)?:\/\//i, '').replace(/^[^@/]*@/, '').split(/[/?]/)[0];
        console.log(`${apply ? 'RESTORING' : 'PLAN ONLY (nothing is changed; add --apply to do it)'} -> ${host}`);
        const { plan } = await restoreFolder({ folder, uri, apply, only, into, log: console.log });
        console.table(plan.map((r) => ({ database: r.db, collection: r.collection, kind: r.kind, 'in backup': r.inBackup, 'already in target': r.alreadyThere, added: apply ? r.added : '-', 'skipped (exists)': apply ? r.skippedExisting : '-', 'indexes added': apply ? r.indexesAdded : '-' })));
        console.log(apply ? 'Done. Nothing existing was overwritten or dropped.' : 'This was only a plan.');
    })().catch((e) => { console.error('Stopped:', e.message); process.exit(1); });
}
