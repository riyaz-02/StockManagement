/**
 * stockRules.js - the "Stock Setting" parameters: how stock, sales, purchases and old metal are valued.
 * One document for the firm (collection app_stock_settings, key "main"). Every value is checked against a fixed
 * list, so a bad request can never store something the app does not understand.
 *
 * Weight bases: fine = pure metal weight (net x purity), final fine = fine + wastage, net, gross.
 */
'use strict';

const BASES4 = ['finalFine', 'fine', 'net', 'gross'];
const YES_NO = [true, false];

// group -> key -> { def: default, allowed: accepted values }
const SCHEMA = {
    addStock: {
        customerWastage: { def: 'fine', allowed: ['fine', 'net', 'gross'] },
        valuation: { def: 'finalFine', allowed: BASES4 },
        makingCharges: { def: 'net', allowed: BASES4 },
        labourCharges: { def: 'net', allowed: BASES4 },
        metalRateByPurity: { def: true, allowed: YES_NO },
        hallmarkGst: { def: true, allowed: YES_NO },
        calculateItemRate: { def: 'byPurity', allowed: ['byPurity', 'default'] },
    },
    sellStock: {
        reverseCalculation: { def: 'makingCharges', allowed: ['makingCharges', 'custWastage', 'metalRate'] },
        makingChargesType: { def: 'addStock', allowed: ['addStock', 'lastEntry', 'userWiseLastEntry'] },
        metalRateByPurity: { def: false, allowed: YES_NO },
        byAddedMetalRate: { def: false, allowed: YES_NO },
        custWastage: { def: 'addStock', allowed: ['addStock', 'lastEntry', 'userWiseLastEntry', 'blank'] },
        hallmarkGst: { def: true, allowed: YES_NO },
    },
    purchase: {
        labourCharges: { def: 'fine', allowed: BASES4 },
        wastage: { def: 'net', allowed: ['fine', 'net', 'gross'] },
        finalValuation: { def: 'net', allowed: BASES4 },
        hallmarkGst: { def: true, allowed: YES_NO },
    },
    oldMetal: {
        receivedValuation: { def: 'fine', allowed: BASES4 },
        rawMetalPurchaseValuation: { def: 'net', allowed: BASES4 },
    },
};

// hallmarking charge and its GST (numbers, not choices)
const HALLMARK_DEFAULT = { charge: 45, type: 'perPiece', cgst: 9, sgst: 9, igst: 18 };
const HALLMARK_NUMBERS = ['charge', 'cgst', 'sgst', 'igst'];

function defaults() {
    const out = {};
    for (const [g, fields] of Object.entries(SCHEMA)) {
        out[g] = {};
        for (const [k, f] of Object.entries(fields)) out[g][k] = f.def;
    }
    out.hallmark = { ...HALLMARK_DEFAULT };
    return out;
}

/** A stored document merged over the defaults (an unknown or invalid stored value falls back to the default). */
function resolve(stored) {
    const d = defaults();
    for (const [g, fields] of Object.entries(SCHEMA)) {
        for (const [k, f] of Object.entries(fields)) {
            const v = stored && stored[g] ? stored[g][k] : undefined;
            if (v !== undefined && f.allowed.includes(v)) d[g][k] = v;
        }
    }
    if (stored && stored.hallmark) {
        const h = stored.hallmark;
        for (const k of HALLMARK_NUMBERS) if (Number.isFinite(Number(h[k])) && Number(h[k]) >= 0 && Number(h[k]) <= 100000) d.hallmark[k] = Number(h[k]);
        if (['perPiece', 'perGram'].includes(h.type)) d.hallmark.type = h.type;
    }
    return d;
}

/** Validate a partial update. Returns { set: { 'group.key': value } } or { error }. */
function validate(body) {
    const set = {};
    for (const [g, fields] of Object.entries(SCHEMA)) {
        if (!body || body[g] === undefined) continue;
        if (typeof body[g] !== 'object' || body[g] === null) return { error: `${g} must be an object` };
        for (const [k, v] of Object.entries(body[g])) {
            const f = fields[k];
            if (!f) return { error: `Unknown setting ${g}.${k}` };
            if (!f.allowed.includes(v)) return { error: `${g}.${k} must be one of ${f.allowed.join(', ')}` };
            set[`${g}.${k}`] = v;
        }
    }
    if (body && body.hallmark !== undefined) {
        for (const [k, v] of Object.entries(body.hallmark || {})) {
            if (HALLMARK_NUMBERS.includes(k)) {
                const n = Number(v);
                if (!Number.isFinite(n) || n < 0 || n > 100000) return { error: `hallmark.${k} must be a number of 0 or more` };
                set[`hallmark.${k}`] = Math.round(n * 100) / 100;
            } else if (k === 'type') {
                if (!['perPiece', 'perGram'].includes(v)) return { error: 'hallmark.type must be perPiece or perGram' };
                set['hallmark.type'] = v;
            } else return { error: `Unknown setting hallmark.${k}` };
        }
    }
    return { set };
}

module.exports = { SCHEMA, defaults, resolve, validate };
