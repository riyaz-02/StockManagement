/**
 * branches.js — branch helpers shared by users and the directory.
 *
 * "main" is a built-in virtual branch: it always exists, is never stored, and
 * is what all pre-branch data and un-assigned users belong to.
 */
'use strict';

const Branch = require('../models/Branch');

const MAIN_BRANCH = { _id: 'main', name: 'Main branch', code: '01', virtual: true };

/** Resolve a branch id to { branchId, branchName }; throws a 400 if unknown. */
async function resolveBranch(id) {
    const key = typeof id === 'string' ? id.trim() : id ? String(id) : '';
    if (!key || key === 'main') return { branchId: 'main', branchName: MAIN_BRANCH.name };
    let b = null;
    try { b = await Branch.findById(key).lean(); } catch (_) { /* invalid ObjectId */ }
    if (!b || b.isActive === false) {
        const err = new Error('Unknown or inactive branch');
        err.statusCode = 400;
        throw err;
    }
    return { branchId: String(b._id), branchName: b.name };
}

module.exports = { MAIN_BRANCH, resolveBranch, Branch };
