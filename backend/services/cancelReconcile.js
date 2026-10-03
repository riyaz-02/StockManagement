/**
 * cancelReconcile.js - when an invoice is cancelled / voided / deleted (on the website: the app has no cancel), the
 * stock pieces it sold go back into stock and the old metal adjusted on it becomes available again.
 *
 * Each invoice is handled ONCE (a row in app_stock_release keeps the list). It only ever touches this app's own data
 * (stock items, boxes, old metal); the invoices collection is only read.
 *   - a piece is restored only if it is still "sold" on THAT invoice number; its box slot is taken back when the slot is
 *     still free, otherwise the piece is left without a box (status active, needs a new place)
 *   - old metal is released only if it still points at that invoice number
 */
'use strict';
const mongoose = require('mongoose');
const logger = require('../config/logger');
const { getConnection } = require('../config/db');

const HIDDEN = ['cancelled', 'void', 'deleted'];
const Release = () => mongoose.connection.collection('app_stock_release');

/** Put a piece that was sold on invoice `number` back into stock (its slot is re-taken when free, else it has no box). */
async function restorePiece(number, itemId) {
    const Item = require('../models/Item');
    const Container = require('../models/Container');
    const it = await Item.findOne({ _id: itemId, status: 'sold', soldInvoice: String(number) });
    if (!it) return false;
    let placed = false;
    if (it.containerId && it.slotNumber) {
        const r = await Container.updateOne({ _id: it.containerId, slots: { $elemMatch: { slotNumber: it.slotNumber, itemId: null } } }, { $set: { 'slots.$.itemId': it._id } });
        placed = r.modifiedCount === 1;
    }
    await Item.updateOne({ _id: it._id }, { $set: { status: 'active', soldInvoice: '', soldAt: null, soldBy: '', ...(placed ? {} : { containerId: null, slotNumber: null }) } });
    return true;
}

async function reconcileCancelled() {
    const OldMetal = require('../models/OldMetal');
    const invoices = getConnection().db.collection('invoices');
    const rows = await invoices.find({
        status: { $in: HIDDEN },
        $or: [{ 'items.item_id': { $exists: true, $ne: '' } }, { old_metal: { $exists: true, $ne: [] } }],
    }).project({ invoice_number: 1, items: 1, old_metal: 1 }).limit(500).toArray();
    if (!rows.length) return { invoices: 0, pieces: 0, oldMetal: 0 };
    const done = new Set((await Release().find({ invoice: { $in: rows.map((r) => String(r.invoice_number)) } }).toArray()).map((x) => x.invoice));
    let pieces = 0, om = 0, count = 0;
    for (const inv of rows) {
        const number = String(inv.invoice_number);
        if (done.has(number)) continue;
        try {
            for (const line of inv.items || []) {
                if (!/^[0-9a-f]{24}$/i.test(String(line.item_id || ''))) continue;
                if (await restorePiece(number, line.item_id)) pieces++;
            }
            for (const o of inv.old_metal || []) {
                if (!/^[0-9a-f]{24}$/i.test(String(o.id || ''))) continue;
                const r = await OldMetal.updateOne({ _id: o.id, usedOnInvoice: number }, { $set: { usedOnInvoice: '' } });
                if (r.modifiedCount) om++;
            }
            await Release().insertOne({ invoice: number, at: new Date() });
            count++;
        } catch (e) { logger.warn(`[cancelReconcile] invoice ${number}: ${e.message}`); }
    }
    if (count) logger.info(`[cancelReconcile] ${count} cancelled invoice(s): ${pieces} piece(s) back in stock, ${om} old metal entr${om === 1 ? 'y' : 'ies'} released`);
    return { invoices: count, pieces, oldMetal: om };
}

module.exports = { reconcileCancelled, restorePiece };
