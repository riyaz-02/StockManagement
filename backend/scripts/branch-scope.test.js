// Branch scoping of the stock models, against the LOCAL test database. Run: node scripts/branch-scope.test.js
'use strict';
require('dotenv').config();
const assert = require('assert');
const mongoose = require('mongoose');
const scope = require('../utils/branchScope');
// the query must be awaited INSIDE the context, as a request handler does
const runWith = (ctx, fn) => scope.runWith(ctx, async () => await fn());
const Item = require('../models/Item');

(async () => {
    const uri = process.env.MONGODB_URI || process.env.MONGO_URI;
    assert(/127\.0\.0\.1|localhost/.test(uri || ''), 'refusing to run: not a local database');
    await mongoose.connect(uri);
    const mk = (barcode, extra = {}) => ({ name: 'BS test ' + barcode, barcode, itemType: 'Ring', metalType: 'Gold', purity: '22K', grossWeight: 5, netWeight: 5, status: 'active', ...extra });
    const tag = 'BST' + Date.now();
    const ok = [];
    const t = async (name, fn) => { await fn(); ok.push(name); console.log('ok -', name); };
    try {
        await runWith({ branchId: 'A1', restrict: ['A1'] }, () => Item.create(mk(tag + 'a')));
        await runWith({ branchId: 'B2', restrict: ['B2'] }, () => Item.create(mk(tag + 'b')));
        await Item.collection.insertOne({ ...mk(tag + 'legacy'), createdAt: new Date() });               // a record from before branches: no branchId
        const names = async (ctx) => (await runWith(ctx, () => Item.find({ name: /^BS test BST/ }).lean())).map((x) => x.barcode).sort();
        await t('new records are stamped with the caller branch', async () => {
            const a = await Item.collection.findOne({ barcode: tag + 'a' });
            assert.strictEqual(a.branchId, 'A1');
        });
        await t('a restricted user only sees their own branch', async () => assert.deepStrictEqual(await names({ branchId: 'A1', restrict: ['A1'] }), [tag + 'a']));
        await t('old records (no branchId) belong to main', async () => {
            assert.deepStrictEqual(await names({ branchId: 'main', restrict: ['main'] }), [tag + 'legacy']);
            assert.ok(!(await names({ branchId: 'B2', restrict: ['B2'] })).includes(tag + 'legacy'));
        });
        await t('the whole-firm view (no restriction) and background jobs see everything', async () => {
            assert.strictEqual((await names({ branchId: 'main', restrict: null })).length, 3);
            assert.strictEqual((await Item.find({ name: /^BS test BST/ }).lean()).length, 3);
        });
        await t('findOne / count / aggregate are scoped too', async () => {
            const ctx = { branchId: 'B2', restrict: ['B2'] };
            assert.strictEqual(await runWith(ctx, () => Item.findOne({ barcode: tag + 'a' })), null);
            assert.strictEqual(await runWith(ctx, () => Item.countDocuments({ name: /^BS test BST/ })), 1);
            const agg = await runWith(ctx, () => Item.aggregate([{ $match: { name: /^BS test BST/ } }, { $group: { _id: null, n: { $sum: 1 } } }]));
            assert.strictEqual(agg[0].n, 1);
        });
        await t('a restricted user cannot update or delete another branch', async () => {
            const ctx = { branchId: 'B2', restrict: ['B2'] };
            const r = await runWith(ctx, () => Item.updateMany({ name: /^BS test BST/ }, { $set: { name: 'BS test BST upd' } }));
            assert.strictEqual(r.modifiedCount, 1);
            const d = await runWith(ctx, () => Item.deleteMany({ name: /^BS test BST/ }));
            assert.strictEqual(d.deletedCount, 1);
            assert.ok(await Item.collection.findOne({ barcode: tag + 'a' }));
        });
        await t('a record\'s own document methods still work (doc.save / doc.deleteOne)', async () => {
            const doc = await runWith({ branchId: 'A1', restrict: ['A1'] }, () => Item.findOne({ barcode: tag + 'a' }));
            doc.name = 'BS test BST saved';
            await runWith({ branchId: 'A1', restrict: ['A1'] }, () => doc.save());
            assert.strictEqual((await Item.collection.findOne({ barcode: tag + 'a' })).name, 'BS test BST saved');
        });
    } finally {
        await Item.collection.deleteMany({ name: /^BS test BST/ });
        await mongoose.disconnect();
    }
    console.log(`\n${ok.length} passed`);
})().catch((e) => { console.error('FAIL', e); process.exit(1); });
