/**
 * gstStates.js — GST state / UT codes for "Place of supply".
 *
 * Stored on invoices exactly like the website does it: "19-West Bengal".
 * (The website's own list has Delhi as 09, and Meghalaya/Nagaland swapped;
 * these are the official GST codes. Old invoices keep whatever they stored.)
 */
'use strict';

const STATES = [
    ['01', 'Jammu & Kashmir'], ['02', 'Himachal Pradesh'], ['03', 'Punjab'], ['04', 'Chandigarh'], ['05', 'Uttarakhand'],
    ['06', 'Haryana'], ['07', 'Delhi'], ['08', 'Rajasthan'], ['09', 'Uttar Pradesh'], ['10', 'Bihar'], ['11', 'Sikkim'],
    ['12', 'Arunachal Pradesh'], ['13', 'Nagaland'], ['14', 'Manipur'], ['15', 'Mizoram'], ['16', 'Tripura'],
    ['17', 'Meghalaya'], ['18', 'Assam'], ['19', 'West Bengal'], ['20', 'Jharkhand'], ['21', 'Odisha'],
    ['22', 'Chhattisgarh'], ['23', 'Madhya Pradesh'], ['24', 'Gujarat'], ['26', 'Dadra & Nagar Haveli and Daman & Diu'],
    ['27', 'Maharashtra'], ['29', 'Karnataka'], ['30', 'Goa'], ['31', 'Lakshadweep'], ['32', 'Kerala'],
    ['33', 'Tamil Nadu'], ['34', 'Puducherry'], ['35', 'Andaman & Nicobar Islands'], ['36', 'Telangana'],
    ['37', 'Andhra Pradesh'], ['38', 'Ladakh'],
].map(([code, name]) => ({ code, name, place: `${code}-${name}` }));

const norm = (s) => String(s || '').toLowerCase().replace(/&/g, 'and').replace(/[^a-z]/g, '');
const ALIASES = { orissa: '21', pondicherry: '34', uttaranchal: '05', andamanandnicobar: '35', jammuandkashmir: '01', dadraandnagarhaveli: '26', damanandiu: '26' };

/** "19-West Bengal" -> {code:'19', name:'West Bengal'} (any text before the first dash is the code). */
function parsePlace(place) {
    const m = String(place || '').match(/^\s*(\d{1,2})\s*-\s*(.+?)\s*$/);
    if (!m) return null;
    const code = m[1].padStart(2, '0');
    const known = STATES.find((s) => s.code === code);
    return { code, name: known ? known.name : m[2] };
}

/** Best match for a free-text state name ("west bengal", "WB"...) -> a state, or null. */
function findByName(name) {
    const n = norm(name);
    if (!n) return null;
    if (ALIASES[n]) return STATES.find((s) => s.code === ALIASES[n]);
    return STATES.find((s) => norm(s.name) === n) || STATES.find((s) => n.length >= 5 && (norm(s.name).startsWith(n) || n.startsWith(norm(s.name)))) || null;
}

/** Only known places are accepted from a client; anything else falls back to the default. */
function normalizePlace(place, fallback = '19-West Bengal') {
    const p = parsePlace(place);
    if (p) {
        const known = STATES.find((s) => s.code === p.code);
        if (known) return known.place;
    }
    const byName = findByName(place);
    return byName ? byName.place : fallback;
}

module.exports = { STATES, parsePlace, findByName, normalizePlace };
