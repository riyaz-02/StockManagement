/**
 * branchScope.js — one place that makes every stock / operations collection branch-aware.
 *
 * How it works
 *  1. `protect` (middleware/auth.js) decides, per request, which branches the caller may see and puts that in an
 *     AsyncLocalStorage context:  { branchId: <branch new records are filed under>, restrict: null | [branch ids] }.
 *       - staff without the "see every branch" permission: restricted to their own branch, always.
 *       - admin / owner / "see every branch": sees the whole firm (restrict = null), or one branch when the app
 *         sends the `X-Branch: <id>` header (branch switcher); `X-Branch: all` = whole firm.
 *  2. `branchPlugin` is added to each stock model. It adds a `branchId` field, stamps it on new records, and adds the
 *     branch filter to every find / count / update / delete / aggregate. So no controller can forget to scope.
 *  3. Background jobs run outside a request: no context, no filter (they see everything).
 *
 * Records that predate branches carry no branchId and belong to the built-in branch "main".
 */
'use strict';

const { AsyncLocalStorage } = require('async_hooks');

const als = new AsyncLocalStorage();

/** Run `fn` with a branch context. */
const runWith = (ctx, fn) => als.run(ctx, fn);
const current = () => als.getStore() || null;

/** Mongo filter for "this record belongs to one of these branches" (old records without a branch count as main). */
function matchFor(ids, field = 'branchId') {
    const list = [...new Set((ids || []).map((x) => String(x || 'main')))];
    const conds = [{ [field]: { $in: list } }];
    if (list.includes('main')) conds.push({ [field]: { $exists: false } }, { [field]: null }, { [field]: '' });
    return conds.length === 1 ? conds[0] : { $or: conds };
}

const QUERY_OPS = [
    'find', 'findOne', 'countDocuments', 'distinct',
    'findOneAndUpdate', 'findOneAndDelete', 'findOneAndReplace', 'findOneAndRemove',
    'updateOne', 'updateMany', 'replaceOne', 'deleteOne', 'deleteMany',
];

function branchPlugin(schema) {
    if (!schema.path('branchId')) schema.add({ branchId: { type: String, index: true } });

    // new records are filed under the caller's current branch
    schema.pre('validate', function stamp(next) {
        if (this.isNew && !this.branchId) {
            const c = current();
            this.branchId = (c && c.branchId) || 'main';
        }
        next();
    });
    schema.pre('insertMany', function stampMany(next, docs) {
        const c = current();
        for (const d of Array.isArray(docs) ? docs : [docs]) if (d && !d.branchId) d.branchId = (c && c.branchId) || 'main';
        next();
    });

    // reads / updates / deletes only touch the caller's branches
    for (const op of QUERY_OPS) {
        schema.pre(op, function scopeQuery(next) {
            const c = current();
            if (typeof this.and !== 'function') return next(); // a document (doc.deleteOne()), not a query
            if (c && c.restrict) this.and([matchFor(c.restrict)]);
            if (c && c.branchId && /^(findOneAndUpdate|updateOne|updateMany)$/.test(op) && this.getOptions().upsert) {
                this.setUpdate({ ...(this.getUpdate() || {}), $setOnInsert: { branchId: c.branchId, ...((this.getUpdate() || {}).$setOnInsert || {}) } });
            }
            next();
        });
    }
    schema.pre('aggregate', function scopeAggregate(next) {
        const c = current();
        if (c && c.restrict) {
            const p = this.pipeline();
            const first = p[0] || {};
            // $geoNear / $search must stay the first stage; nothing here uses them, but be safe
            const at = first.$geoNear || first.$search || first.$vectorSearch ? 1 : 0;
            p.splice(at, 0, { $match: matchFor(c.restrict) });
        }
        next();
    });
}

module.exports = { branchPlugin, runWith, current, matchFor };
