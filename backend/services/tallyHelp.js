/**
 * tallyHelp.js - pure helpers for the stock tally (no database here, so they can be tested).
 *
 * A tally is a photograph of what should be in the shop when it starts (the `items` list of the session). Staff then scan
 * every piece. Two things make the flow forgiving:
 *   - a piece SOLD after the tally started is no longer expected on the shelf: it is set aside ("sold since"), it never blocks
 *     the tally and its weight is taken off what was expected;
 *   - what is left to find is shown BOX BY BOX with the slot, so staff know where to look.
 */
'use strict';

const r3 = (n) => Math.round((Number(n) + Number.EPSILON) * 1000) / 1000;
const GONE = ['sold', 'deleted'];

/** Group a tally's pieces by box. `pieces`: [{ id, scanned, containerId, containerName, weight, ... }] */
function boxProgress(pieces) {
    const map = new Map();
    for (const p of pieces) {
        if (p.gone) continue;                             // sold since: not on the shelf any more
        const key = p.containerId || '';
        if (!map.has(key)) map.set(key, { id: key, name: key ? p.containerName || 'Box' : 'Not in any box', total: 0, scanned: 0 });
        const b = map.get(key);
        b.total += 1;
        if (p.scanned) b.scanned += 1;
    }
    const boxes = [...map.values()].map((b) => ({ ...b, missing: b.total - b.scanned }));
    // unfinished boxes first (most left to do first), finished ones last
    boxes.sort((a, b) => (a.missing === 0) - (b.missing === 0) || b.missing - a.missing || String(a.name).localeCompare(String(b.name)));
    return boxes;
}

/**
 * Split the pieces into scanned / still to find / sold since, and work out what is really expected.
 * Returns { scanned, missing, soldSince, expectedItems, expectedWeight: { [metal]: g }, soldWeight: { [metal]: g } }
 */
function reconcile(pieces) {
    const out = { scanned: [], missing: [], soldSince: [], expectedItems: 0, expectedWeight: {}, soldWeight: {} };
    for (const p of pieces) {
        const metal = String(p.metalType || '').toLowerCase();
        if (p.gone) {
            out.soldSince.push(p);
            out.soldWeight[metal] = r3((out.soldWeight[metal] || 0) + (Number(p.weight) || 0));
            continue;
        }
        out.expectedItems += 1;
        out.expectedWeight[metal] = r3((out.expectedWeight[metal] || 0) + (Number(p.weight) || 0));
        (p.scanned ? out.scanned : out.missing).push(p);
    }
    return out;
}

module.exports = { GONE, boxProgress, reconcile, r3 };
