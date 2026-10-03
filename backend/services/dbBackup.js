/**
 * dbBackup.js - a complete, READ-ONLY copy of one or more MongoDB databases, streamed out as a .zip.
 *
 * Why it exists: the free Atlas tier has no backups, so the owner pastes a connection string on the website and gets
 * every document back as a file he can keep. Nothing here ever writes to the source database: the only calls made are
 * ping, listDatabases, listCollections, collStats, estimatedDocumentCount, indexes and find.
 *
 * What is in the zip (the layout is the same one `mongodump` writes, so the official `mongorestore` reads it as is):
 *   dump/<db>/<collection>.bson            every document, byte for byte (exact types: int32 / int64 / double / decimal / dates)
 *   dump/<db>/<collection>.metadata.json   indexes and collection options (a view is only this file: it holds its definition)
 *   readable/<db>/<collection>.jsonl       the same documents as plain text, one per line, to LOOK at (optional)
 *   manifest.json                          counts and a SHA-256 per file, so a bad copy is noticed
 *   README-restore.txt                     how to put it back
 *
 * The connection string (it holds a password) is used for this one call: never stored, never logged, and scrubbed out of
 * every error message.
 */
'use strict';
const crypto = require('crypto');
const { Readable } = require('stream');
const { MongoClient, BSON } = require('mongoose').mongo;
const archiver = require('archiver');

const { EJSON } = BSON;
const SYSTEM_DBS = new Set(['admin', 'local', 'config']);
const connectMs = () => Number(process.env.BACKUP_CONNECT_MS) || 12000;

class BackupError extends Error {
    constructor(message, status = 400) {
        super(message);
        this.name = 'BackupError';
        this.status = status;
    }
}

let busy = false; // one backup at a time: a second would only compete for the same (small) database

// ── the connection string ────────────────────────────────────────────────────────────────────────────────────────

function validateUri(raw) {
    const uri = String(raw || '').trim();
    if (!uri) throw new BackupError('Paste the MongoDB connection string first');
    if (uri.length > 2000) throw new BackupError('That connection string is too long');
    if (!/^mongodb(\+srv)?:\/\//i.test(uri)) throw new BackupError('The connection string must start with mongodb:// or mongodb+srv://');
    return uri;
}

/** Host(s) and the default database named in the address: safe to show (no user, no password). */
function describeUri(uri) {
    const rest = uri.replace(/^mongodb(\+srv)?:\/\//i, '').replace(/^[^@/]*@/, '');
    const host = rest.split(/[/?]/)[0] || 'database';
    const m = /^[^/]*\/([^?]*)/.exec(rest);
    let defaultDb = '';
    try { defaultDb = m && m[1] ? decodeURIComponent(m[1]) : ''; } catch { defaultDb = ''; }
    return { host, defaultDb };
}

/** Remove the address and the credentials from any text before it can reach a log or a screen. */
function scrub(text, uri) {
    let out = String(text == null ? '' : text);
    const parts = [uri];
    const m = /^mongodb(?:\+srv)?:\/\/([^@/]+)@/i.exec(uri || '');
    if (m) {
        parts.push(m[1]);
        const i = m[1].indexOf(':');
        const user = i >= 0 ? m[1].slice(0, i) : m[1];
        const pass = i >= 0 ? m[1].slice(i + 1) : '';
        for (const x of [user, pass]) {
            if (x.length < 4) continue; // a very short secret would mangle ordinary words
            parts.push(x);
            try { parts.push(decodeURIComponent(x)); } catch { /* not encoded */ }
        }
    }
    for (const p of [...new Set(parts)].filter(Boolean).sort((a, b) => b.length - a.length)) out = out.split(p).join('***');
    return out;
}

function friendly(e, uri) {
    const msg = scrub(e && e.message ? e.message : e, uri);
    const name = (e && e.name) || '';
    if ((e && (e.code === 18 || e.code === 8000 || e.codeName === 'AuthenticationFailed')) || (/auth/i.test(msg) && /fail|denied|bad/i.test(msg))) {
        return 'The database did not accept the username or password.';
    }
    if (/MongoParseError|MongoAPIError/.test(name) || /Invalid (scheme|connection string)|mongodb\+srv/i.test(msg) && !/ENOTFOUND|querySrv/i.test(msg)) {
        return `That connection string is not valid: ${msg}`;
    }
    if (/MongoServerSelectionError|MongoNetworkError/.test(name) || /ENOTFOUND|EAI_AGAIN|querySrv|ECONNREFUSED|timed out/i.test(msg)) {
        return "Could not reach the database. Check the address, your internet, and that this server's IP address is allowed in Atlas (Network Access).";
    }
    return msg || 'The database refused the request.';
}

async function open(uri) {
    const client = new MongoClient(uri, { serverSelectionTimeoutMS: connectMs(), connectTimeoutMS: connectMs(), maxPoolSize: 2, appName: 'lgp-backup' });
    try {
        await client.connect();
        await client.db('admin').command({ ping: 1 });
    } catch (e) {
        await client.close().catch(() => {});
        throw new BackupError(friendly(e, uri));
    }
    return client;
}

// ── what is there ────────────────────────────────────────────────────────────────────────────────────────────────

async function visibleDatabases(client, defaultDb) {
    let names = [];
    try {
        const r = await client.db('admin').command({ listDatabases: 1, nameOnly: true, authorizedDatabases: true });
        names = (r.databases || []).map((d) => d.name);
    } catch { /* this user may not list databases: fall back to the one named in the address */ }
    names = names.filter((n) => !SYSTEM_DBS.has(n));
    if (!names.length && defaultDb && !SYSTEM_DBS.has(defaultDb)) names = [defaultDb];
    return names.sort((a, b) => (a === defaultDb ? -1 : b === defaultDb ? 1 : a.localeCompare(b)));
}

async function collectionsOf(db) {
    const list = await db.listCollections({}, { nameOnly: false }).toArray();
    return list
        .filter((c) => !c.name.startsWith('system.'))
        .map((c) => ({ name: c.name, type: c.type || 'collection', options: c.options || {} }))
        .sort((a, b) => a.name.localeCompare(b.name));
}

async function sizeInfo(db, c) {
    if (c.type === 'view') return { count: null, sizeBytes: null };
    let count = null;
    let sizeBytes = null;
    try { count = await db.collection(c.name).estimatedDocumentCount(); } catch { /* shown as unknown */ }
    try { sizeBytes = (await db.command({ collStats: c.name })).size; } catch { /* some plans do not allow it */ }
    return { count, sizeBytes };
}

/** For the page: connect, list every database and collection with counts and sizes. Reads nothing else. */
async function inspect(rawUri) {
    const uri = validateUri(rawUri);
    const { host, defaultDb } = describeUri(uri);
    const client = await open(uri);
    try {
        const databases = [];
        for (const name of await visibleDatabases(client, defaultDb)) {
            const db = client.db(name);
            const cols = await collectionsOf(db);
            const collections = [];
            for (const c of cols) collections.push({ name: c.name, type: c.type, ...(await sizeInfo(db, c)) });
            databases.push({
                name, isDefault: name === defaultDb, collections,
                totalDocs: collections.reduce((a, c) => a + (c.count || 0), 0),
                totalBytes: collections.reduce((a, c) => a + (c.sizeBytes || 0), 0),
            });
        }
        return { host, defaultDb, databases };
    } catch (e) {
        throw e instanceof BackupError ? e : new BackupError(friendly(e, uri));
    } finally {
        await client.close().catch(() => {});
    }
}

// ── the backup ───────────────────────────────────────────────────────────────────────────────────────────────────

const safe = (s) => String(s).replace(/[^A-Za-z0-9._-]/g, '_');
const stampOf = (d) => d.toISOString().replace(/[-:]/g, '').replace(/\..*/, '').replace('T', '-');

function appendStream(archive, stream, name) {
    return new Promise((resolve, reject) => {
        stream.on('end', resolve);
        stream.on('error', reject);
        archive.append(stream, { name });
    });
}

function readmeText(m) {
    return [
        'LGP raw database backup',
        `Taken: ${m.createdAt} (UTC)`,
        `From:  ${m.source.host}   (the user name and password are never written into this file)`,
        `Saved: ${m.databases.map((d) => `${d.name} (${d.collections.length} collections)`).join(', ')}`,
        '',
        'WHAT IS INSIDE',
        '  dump/<database>/<collection>.bson            every document, exactly as stored (MongoDB\'s own dump format)',
        '  dump/<database>/<collection>.metadata.json   the indexes and options of that collection (a view is only this file)',
        m.readableIncluded ? '  readable/<database>/<collection>.jsonl       the same documents as plain text, one per line. For LOOKING only; restore from dump/' : '  (no readable text copy was asked for)',
        '  manifest.json                                how many documents and a SHA-256 fingerprint for every file',
        '',
        'HOW TO PUT IT BACK',
        '  Needs the free "MongoDB Database Tools" (https://www.mongodb.com/try/download/database-tools). Unzip this file first.',
        '  1. Look first, change nothing:   mongorestore --uri "<TARGET ADDRESS>" --dryRun dump',
        '  2. Everything:                   mongorestore --uri "<TARGET ADDRESS>" dump',
        '  3. One collection only:          mongorestore --uri "<TARGET ADDRESS>" --nsInclude "<database>.<collection>" dump',
        '  4. Into a different database:    mongorestore --uri "<TARGET ADDRESS>" --nsFrom "<database>.*" --nsTo "<newdatabase>.*" dump',
        '  By default mongorestore only ADDS what is missing: a document that already exists (same _id) is left alone.',
        '  Never add --drop to a live database unless you really mean to throw its current data away first.',
        '',
        'NO DATABASE TOOLS? Use the script that comes with the project (it also only adds what is missing, and shows a plan first):',
        '  node backend/scripts/restore-backup.js "<unzipped folder>" "<TARGET ADDRESS>"            (plan only)',
        '  node backend/scripts/restore-backup.js "<unzipped folder>" "<TARGET ADDRESS>" --apply    (do it)',
        '',
        'CHECKING THIS COPY: manifest.json lists, per collection, the number of documents and the SHA-256 of its .bson file.',
        '',
    ].join('\n');
}

async function writeZip(client, plan, host, includeReadable, out) {
    const startedAt = new Date();
    const top = `lgp-backup-${stampOf(startedAt)}`;
    const archive = archiver('zip', { zlib: { level: 6 } });
    const finished = new Promise((resolve, reject) => {
        archive.on('error', reject);
        archive.on('warning', (w) => { if (w.code !== 'ENOENT') reject(w); });
        out.on('error', reject);
        out.on('finish', resolve);
        out.on('close', () => { if (!out.writableFinished) reject(new BackupError('The download was cancelled before it finished', 499)); });
    });
    finished.catch(() => {}); // reported where it is awaited below
    archive.pipe(out);

    const manifest = {
        tool: 'LGP raw backup', createdAt: startedAt.toISOString(), source: { host },
        format: 'dump/ = mongodump layout (bson + metadata.json); readable/ = one relaxed Extended JSON document per line',
        readableIncluded: includeReadable, databases: [],
    };
    let documents = 0;
    let collections = 0;
    try {
        for (const dbPlan of plan) {
            const dbEntry = { name: dbPlan.name, collections: [] };
            for (const c of dbPlan.collections) {
                const col = client.db(dbPlan.name).collection(c.name);
                const base = `${top}/dump/${safe(dbPlan.name)}/${safe(c.name)}`;
                if (c.type === 'view') {
                    archive.append(EJSON.stringify({ options: c.options, indexes: [] }, { relaxed: false }), { name: `${base}.metadata.json` });
                    dbEntry.collections.push({ name: c.name, type: 'view', options: JSON.parse(EJSON.stringify(c.options, { relaxed: true })), note: 'definition only: a view holds no data of its own' });
                    continue;
                }
                const sha = crypto.createHash('sha256');
                let count = 0;
                let bytes = 0;
                const cursor = col.find({}, { raw: true, batchSize: 500 });
                const bson = Readable.from((async function* () {
                    for await (const buf of cursor) { count += 1; bytes += buf.length; sha.update(buf); yield buf; }
                })(), { objectMode: false });
                await appendStream(archive, bson, `${base}.bson`);

                const indexes = (await col.indexes().catch(() => [])).map(({ ns, ...rest }) => rest);
                archive.append(EJSON.stringify({ options: c.options, indexes }, { relaxed: false }), { name: `${base}.metadata.json` });

                let readableDocs = null;
                if (includeReadable) {
                    readableDocs = 0;
                    const text = Readable.from((async function* () {
                        for await (const doc of col.find({}, { batchSize: 500 })) { readableDocs += 1; yield `${EJSON.stringify(doc, { relaxed: true })}\n`; }
                    })(), { objectMode: false });
                    await appendStream(archive, text, `${top}/readable/${safe(dbPlan.name)}/${safe(c.name)}.jsonl`);
                }
                dbEntry.collections.push({
                    name: c.name, type: 'collection', documents: count, documentsExpectedAtStart: c.count, bytes, sha256: sha.digest('hex'),
                    file: `dump/${safe(dbPlan.name)}/${safe(c.name)}.bson`, indexes: indexes.length, readableDocuments: readableDocs,
                });
                documents += count;
                collections += 1;
            }
            manifest.databases.push(dbEntry);
        }
        archive.append(JSON.stringify(manifest, null, 2), { name: `${top}/manifest.json` });
        archive.append(readmeText(manifest), { name: `${top}/README-restore.txt` });
        await archive.finalize();
        await finished;
    } catch (e) {
        archive.abort();
        out.destroy();
        throw e;
    }
    return { host, databases: manifest.databases.length, collections, documents, bytes: archive.pointer(), readableIncluded: includeReadable, filename: `${top}.zip` };
}

/**
 * Read the chosen databases (default: every one this login can see) and stream them as a zip into the writable that
 * `getOutput({filename})` returns. `getOutput` is only called once the connection works and the plan is valid, so a
 * wrong password or a mistyped database name is still a normal error answer, not a broken download.
 */
async function backup(rawUri, { databases = [], includeReadable = true } = {}, getOutput) {
    if (busy) throw new BackupError('Another backup is running right now. Try again in a minute.', 409);
    busy = true;
    let client = null;
    let uri = '';
    try {
        uri = validateUri(rawUri);
        const { host, defaultDb } = describeUri(uri);
        client = await open(uri);
        const visible = await visibleDatabases(client, defaultDb);
        const wanted = databases.length ? databases : visible;
        for (const name of wanted) {
            if (!visible.includes(name)) throw new BackupError(`The database "${name}" was not found, or this login may not read it.`);
        }
        const plan = [];
        for (const name of wanted) {
            const db = client.db(name);
            const cols = await collectionsOf(db);
            const withCount = [];
            for (const c of cols) withCount.push({ ...c, count: (await sizeInfo(db, c)).count });
            plan.push({ name, collections: withCount });
        }
        if (!plan.some((d) => d.collections.length)) throw new BackupError('Nothing to back up: no collections were found in the chosen database(s).');
        const label = `${safe(host.split(',')[0].split(':')[0])}`;
        const out = getOutput({ filename: `lgp-backup-${label}-${stampOf(new Date())}.zip` });
        return await writeZip(client, plan, host, includeReadable !== false, out);
    } catch (e) {
        throw e instanceof BackupError ? e : new BackupError(friendly(e, uri), 500);
    } finally {
        busy = false;
        if (client) await client.close().catch(() => {});
    }
}

module.exports = { inspect, backup, BackupError, scrub, validateUri, describeUri };
