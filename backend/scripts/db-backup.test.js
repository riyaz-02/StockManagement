// The "Data backup" service and the restore script, against the LOCAL dev database only. Run: node scripts/db-backup.test.js
// Builds two throw-away databases, backs one up, restores it into a copy and proves: every document comes back byte for byte,
// indexes / views / options survive, the source is never changed, a wrong address never leaks its password, and a second
// backup at the same time is refused. The throw-away databases are always dropped.
'use strict';
require('dotenv').config();
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { Writable } = require('stream');
const JSZip = require('jszip');
const { MongoClient, BSON } = require('mongoose').mongo;
const svc = require('../services/dbBackup');
const { restoreFolder } = require('./restore-backup');

const { Int32, Double, Long, Decimal128, Binary, ObjectId, BSONRegExp, MinKey } = BSON;
const m = /^(mongodb:\/\/(?:127\.0\.0\.1|localhost)(?::\d+)?)/.exec(process.env.MONGODB_URI || '');
assert(m, 'refusing to run: MONGODB_URI is not a local database');
const BASE = m[1];
const tag = `${Date.now()}`;
const SRC = `bk_src_${tag}`;
const SRC2 = `bk_src2_${tag}`;
const DST = `bk_dst_${tag}`;
const ok = (name) => console.log('ok -', name);

const rawAll = async (db, coll) => (await db.collection(coll).find({}, { raw: true, sort: { _id: 1 } }).toArray());
const fingerprint = async (db) => {
    const h = crypto.createHash('sha256');
    for (const c of (await db.listCollections().toArray()).filter((x) => x.type !== 'view').sort((a, b) => a.name.localeCompare(b.name))) {
        h.update(c.name);
        for (const b of await rawAll(db, c.name)) h.update(b);
    }
    return h.digest('hex');
};

(async () => {
    const client = new MongoClient(BASE, { serverSelectionTimeoutMS: 8000 });
    await client.connect();
    const src = client.db(SRC);
    const src2 = client.db(SRC2);
    const dst = client.db(DST);
    const work = fs.mkdtempSync(path.join(os.tmpdir(), 'bk-test-'));
    try {
        // ── a source with awkward data ──
        const oid = new ObjectId();
        await src.collection('people').insertMany([
            { _id: oid, name: 'Ravi', email: 'ravi@example.com', age: new Int32(41), weight: new Double(5), big: Long.fromNumber(2 ** 40), price: Decimal128.fromString('14047.55'), joined: new Date('2024-03-09T10:11:12.345Z'), blob: new Binary(Buffer.from([0, 1, 2, 250, 255])), tags: ['gold', 'পরীক্ষা', '💍'], nested: { a: { b: [1, 2, { c: null }] } }, re: new BSONRegExp('^ab+', 'i'), lo: new MinKey() },
            { _id: new ObjectId(), name: 'সম্পাদিত', email: 'bn@example.com', age: 30, active: true },
            { _id: 'string-id', name: 'string id', email: 'sid@example.com' },
            { _id: 42, name: 'number id', email: 'n42@example.com' },
        ]);
        await src.collection('people').createIndex({ email: 1 }, { unique: true, name: 'email_unique' });
        await src.collection('people').createIndex({ joined: 1 }, { name: 'joined_ttl', expireAfterSeconds: 3600 * 24 * 365 * 50, sparse: true });
        await src.createCollection('empty_one');
        await src.createCollection('log_capped', { capped: true, size: 100000 });
        await src.collection('log_capped').insertMany([{ n: 1 }, { n: 2 }]);
        await src.createCollection('people_view', { viewOn: 'people', pipeline: [{ $match: { age: { $exists: true } } }] });
        await src2.collection('other').insertOne({ keep: 'out of the first backup' });
        const before = { src: await fingerprint(src), src2: await fingerprint(src2) };

        // ── inspect ──
        const info = await svc.inspect(`${BASE}/${SRC}`);
        const dbs = Object.fromEntries(info.databases.map((d) => [d.name, d]));
        assert(dbs[SRC] && dbs[SRC2], 'both databases are listed');
        assert(!info.databases.some((d) => ['admin', 'local', 'config'].includes(d.name)), 'system databases are left out');
        assert.strictEqual(info.databases[0].name, SRC, 'the database named in the address comes first');
        assert.strictEqual(dbs[SRC].collections.find((c) => c.name === 'people').count, 4);
        assert.strictEqual(dbs[SRC].collections.find((c) => c.name === 'people_view').type, 'view');
        assert(!/@/.test(info.host), 'the host shown has no credentials');
        ok('inspect lists databases, collections, counts and views, and hides system databases');

        // ── back up one database to a file ──
        const zipPath = path.join(work, 'b.zip');
        let gotName = '';
        const sum = await svc.backup(`${BASE}/${SRC}`, { databases: [SRC] }, ({ filename }) => { gotName = filename; return fs.createWriteStream(zipPath); });
        assert(/^lgp-backup-.+\.zip$/.test(gotName) && sum.documents === 6, `summary: ${JSON.stringify(sum)}`);
        const zip = await JSZip.loadAsync(fs.readFileSync(zipPath));
        const names = Object.keys(zip.files).filter((n) => !zip.files[n].dir);
        const top = names[0].split('/')[0];
        for (const must of ['manifest.json', 'README-restore.txt', `dump/${SRC}/people.bson`, `dump/${SRC}/people.metadata.json`, `dump/${SRC}/empty_one.bson`, `dump/${SRC}/people_view.metadata.json`, `readable/${SRC}/people.jsonl`]) {
            assert(names.includes(`${top}/${must}`), `zip has ${must}`);
        }
        assert(!names.some((n) => n.includes(SRC2)), 'a database that was not chosen is not in the zip');
        assert(!names.some((n) => n.endsWith('people_view.bson')), 'a view has no data file');
        ok('the zip has the dump layout, readable copies, manifest and README, and only the chosen database');

        // ── manifest honesty ──
        const manifest = JSON.parse(await zip.file(`${top}/manifest.json`).async('string'));
        const people = manifest.databases[0].collections.find((c) => c.name === 'people');
        const peopleBson = await zip.file(`${top}/dump/${SRC}/people.bson`).async('nodebuffer');
        assert.strictEqual(people.documents, 4);
        assert.strictEqual(people.documentsExpectedAtStart, 4);
        assert.strictEqual(people.bytes, peopleBson.length);
        assert.strictEqual(people.sha256, crypto.createHash('sha256').update(peopleBson).digest('hex'));
        assert.strictEqual(people.readableDocuments, 4);
        assert(!/mongodb:\/\//i.test(JSON.stringify(manifest)) && !/README/.test('') , 'no address in the manifest');
        const readme = await zip.file(`${top}/README-restore.txt`).async('string');
        assert(/mongorestore/.test(readme) && !/mongodb:\/\//i.test(readme), 'README explains the restore and holds no address');
        ok('manifest counts and SHA-256 match the files; no address or password is written anywhere in the zip');

        // ── the readable copy parses and keeps the text ──
        const lines = (await zip.file(`${top}/readable/${SRC}/people.jsonl`).async('string')).trim().split('\n').map((l) => JSON.parse(l));
        assert.strictEqual(lines.length, 4);
        assert(lines.some((d) => d.name === 'সম্পাদিত'), 'Bengali text is intact in the readable copy');
        ok('the readable copy is valid and keeps non-English text');

        // ── restore into a copy and compare byte for byte ──
        for (const n of names) {
            const out = path.join(work, 'unzipped', n);
            fs.mkdirSync(path.dirname(out), { recursive: true });
            fs.writeFileSync(out, await zip.file(n).async('nodebuffer'));
        }
        const folder = path.join(work, 'unzipped', top);
        const plan = await restoreFolder({ folder, uri: `${BASE}`, only: SRC, into: DST });
        assert.strictEqual(plan.applied, false);
        assert.deepStrictEqual((await dst.listCollections().toArray()).length, 0, 'a plan changes nothing');
        const real = await restoreFolder({ folder, uri: `${BASE}`, only: SRC, into: DST, apply: true });
        const sameBytes = async (coll) => {
            const a = await rawAll(src, coll);
            const b = await rawAll(dst, coll);
            assert.strictEqual(a.length, b.length, `${coll}: same number of documents`);
            a.forEach((x, i) => assert(Buffer.compare(x, b[i]) === 0, `${coll}: document ${i} is byte-identical`));
        };
        await sameBytes('people');
        await sameBytes('log_capped');
        assert.strictEqual((await rawAll(dst, 'empty_one')).length, 0);
        assert.strictEqual(real.plan.find((r) => r.collection === 'people').added, 4);
        ok('restore into a copy gives back every document byte for byte (all the awkward types and ids)');

        const idx = (await dst.collection('people').indexes()).map((i) => i.name).sort();
        assert.deepStrictEqual(idx, ['_id_', 'email_unique', 'joined_ttl']);
        const uniq = (await dst.collection('people').indexes()).find((i) => i.name === 'email_unique');
        assert.strictEqual(uniq.unique, true);
        assert.strictEqual((await dst.collection('people').indexes()).find((i) => i.name === 'joined_ttl').expireAfterSeconds, 3600 * 24 * 365 * 50);
        assert((await dst.listCollections({ name: 'log_capped' }).toArray())[0].options.capped === true, 'capped option kept');
        const view = (await dst.listCollections({ name: 'people_view' }).toArray())[0];
        assert(view && view.type === 'view', 'the view is recreated');
        assert.strictEqual((await dst.collection('people_view').find().toArray()).length, 2, 'the view works');
        ok('indexes (unique, TTL), capped options and views are recreated');

        // ── restoring again never overwrites or duplicates ──
        await dst.collection('people').updateOne({ _id: 42 }, { $set: { name: 'EDITED AFTER RESTORE' } });
        const again = await restoreFolder({ folder, uri: `${BASE}`, only: SRC, into: DST, apply: true });
        const r2 = again.plan.find((r) => r.collection === 'people');
        assert.strictEqual(r2.added, 0);
        assert.strictEqual(r2.skippedExisting, 4);
        assert.strictEqual((await dst.collection('people').findOne({ _id: 42 })).name, 'EDITED AFTER RESTORE', 'an existing document is left alone');
        ok('a second restore adds nothing and never overwrites what is already there');

        // ── the source was never touched ──
        assert.strictEqual(await fingerprint(src), before.src);
        assert.strictEqual(await fingerprint(src2), before.src2);
        ok('the source databases are byte-for-byte unchanged after inspect + backup');

        // ── errors: wrong things are explained, passwords never leak ──
        process.env.BACKUP_CONNECT_MS = '1500';
        const leak = 'Sup3rS3cretPw';
        const bad = await svc.inspect(`mongodb://someone:${leak}@127.0.0.1:1/x`).then(() => null, (e) => e);
        assert(bad instanceof svc.BackupError && !bad.message.includes(leak) && /reach/i.test(bad.message), `unreachable: ${bad && bad.message}`);
        for (const [uri, rx] of [['', /Paste/], ['http://x', /must start with mongodb/], ['mongodb://' + 'a'.repeat(2100), /too long/]]) {
            const e = await svc.inspect(uri).then(() => null, (x) => x);
            assert(e instanceof svc.BackupError && rx.test(e.message), `bad address "${uri.slice(0, 12)}": ${e && e.message}`);
        }
        assert(!svc.scrub(`failed for user:${leak}@host and ${leak}`, `mongodb://user:${leak}@host/db`).includes(leak));
        const missing = await svc.backup(`${BASE}/${SRC}`, { databases: ['no_such_db_' + tag] }, () => { throw new Error('must not start a download'); }).then(() => null, (e) => e);
        assert(missing instanceof svc.BackupError && /not found/.test(missing.message));
        ok('bad or unreachable addresses and unknown databases give clear errors, and a password never appears in one');

        // ── one backup at a time ──
        let firstWrite = true;
        const slow = () => new Writable({ write(c, e, cb) { if (firstWrite) { firstWrite = false; setTimeout(cb, 500); } else cb(); } });
        const first = svc.backup(`${BASE}/${SRC}`, { databases: [SRC] }, () => slow());
        const second = await svc.backup(`${BASE}/${SRC}`, { databases: [SRC] }, () => slow()).then(() => null, (e) => e);
        assert(second instanceof svc.BackupError && second.status === 409, 'a second backup while one runs is refused');
        await first;
        const third = await svc.backup(`${BASE}/${SRC}`, { databases: [SRC] }, () => fs.createWriteStream(path.join(work, 't.zip'))).catch((e) => e);
        assert(third && third.documents === 6, 'and a new one is accepted once the first is finished');
        ok('only one backup runs at a time, and the next one is allowed afterwards');

        console.log('\nall db-backup checks passed');
    } finally {
        await src.dropDatabase().catch(() => {});
        await src2.dropDatabase().catch(() => {});
        await dst.dropDatabase().catch(() => {});
        await client.close().catch(() => {});
        fs.rmSync(work, { recursive: true, force: true });
    }
})().catch((e) => { console.error('FAILED:', e && e.stack || e); process.exit(1); });
