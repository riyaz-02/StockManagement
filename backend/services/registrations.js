/**
 * registrations.js — GST is filed per GSTIN ("registration"), not per shop.
 *
 * The firm has ONE default registration (the seller GSTIN in the GST configuration) that covers the main branch and
 * every branch that has no GSTIN of its own. A branch that has its own valid GSTIN (state-wise registration) is
 * a separate registration: its own returns, due dates, ITC balance and reminders. Branches sharing one GSTIN are
 * grouped together.
 *
 *   { key: <gstin>, gstin, name, stateCode, isDefault, branchIds: ['main', ...], branches: [{id, name}] }
 */
'use strict';
const { getSeller } = require('./billingSeller');
const { Branch } = require('../utils/branches');
const { current, matchFor } = require('../utils/branchScope');

const GSTIN = /^\d{2}[A-Z0-9]{13}$/;

async function loadRegistrations() {
    const seller = await getSeller();
    const def = { key: seller.gstin, gstin: seller.gstin, name: seller.firmName, stateCode: String(seller.stateCode || String(seller.gstin || '').slice(0, 2) || '19'), isDefault: true, branchIds: ['main'], branches: [{ id: 'main', name: 'Main branch' }] };
    const list = [def];
    // Branch is an app collection (not branch-scoped), so this sees all of them
    const branches = await Branch.find({ isActive: { $ne: false } }).sort({ name: 1 }).lean();
    for (const b of branches) {
        const id = String(b._id);
        const g = String(b.gstin || '').toUpperCase().trim();
        if (!GSTIN.test(g) || g === def.gstin) { def.branchIds.push(id); def.branches.push({ id, name: b.name }); continue; }
        let r = list.find((x) => x.gstin === g);
        if (!r) { r = { key: g, gstin: g, name: `${seller.firmName} (${b.state || b.name})`, stateCode: g.slice(0, 2), isDefault: false, branchIds: [], branches: [] }; list.push(r); }
        r.branchIds.push(id); r.branches.push({ id, name: b.name });
    }
    return list;
}

/** The registrations a request may see (staff limited to their branch see only the registration that holds it). */
async function visibleRegistrations(req) {
    const all = await loadRegistrations();
    const restrict = req.branchScope && req.branchScope.restrict;
    return restrict ? all.filter((r) => r.branchIds.some((b) => restrict.includes(b))) : all;
}

/**
 * Which branches a report covers.  `gstin`: '' = default registration, 'all' = every visible registration, or a GSTIN.
 * `branch`: narrow to one branch. Returns { registration, registrations, branchIds: null (no filter) | [ids], partial }.
 */
async function reportScope(req, { gstin = '', branch = '' } = {}) {
    const regs = await visibleRegistrations(req);
    const restrict = req.branchScope && req.branchScope.restrict;
    gstin = String(gstin || '').trim().toUpperCase();
    let registration = null, ids = null;
    if (gstin === 'ALL') {
        ids = restrict ? [...restrict] : null;
    } else {
        registration = gstin ? regs.find((r) => r.gstin === gstin) : (regs.find((r) => r.isDefault) || regs[0]);
        if (!registration) return { error: 'You do not have access to that GSTIN', registrations: regs };
        ids = registration.branchIds.filter((b) => !restrict || restrict.includes(b));
    }
    branch = String(branch || '').trim();
    if (branch) ids = ids === null ? [branch] : ids.filter((b) => b === branch);
    return { registration, registrations: regs, branchIds: ids, partial: !!restrict };
}

module.exports = { loadRegistrations, visibleRegistrations, reportScope, salesFilter: (ids) => (ids === null ? {} : matchFor(ids, 'branch_id')), stockFilter: (ids) => (ids === null ? {} : matchFor(ids)), current };
