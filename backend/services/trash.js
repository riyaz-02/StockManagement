/**
 * trash.js — a copy of a record that was removed from a collection the website shares (e.g. `purchases`).
 *
 * The website has no "deleted" flag for those collections and lists every document it finds, so the app cannot hide a record
 * with its own flag: it removes it for real, and keeps the whole document here (`app_trash`) so it can be put back by hand.
 * Never throws: the record is already gone, a failed copy must not fail the request (it is logged).
 */
'use strict';
const { getConnection } = require('../config/db');

async function keep(req, collection, doc, label) {
    try {
        const plain = typeof doc.toObject === 'function' ? doc.toObject() : doc;
        await getConnection().db.collection('app_trash').insertOne({
            collection, docId: plain._id, label: String(label || '').slice(0, 160), doc: plain,
            deletedAt: new Date(),
            by: req && req.user ? String(req.user._id || req.user.id) : '', byName: (req && req.user && req.user.name) || '',
        });
    } catch (e) {
        console.error('[trash] could not keep a copy:', e.message);
    }
}

module.exports = { keep };
