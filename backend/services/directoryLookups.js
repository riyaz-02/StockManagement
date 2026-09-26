/**
 * directoryLookups.js — helpers that fill in form fields automatically.
 *
 *  - toBengali():   English -> Bengali for names, nicknames and addresses
 *                   (what the LGPAdmin website does with Google Translate).
 *  - pincode():     6-digit pincode -> state / district / post offices
 *  - ifsc():        IFSC code -> bank / branch / city / state
 *
 * Everything is fail-soft: on any upstream problem the function returns null
 * and the form simply stays manual. Results are cached in memory.
 *
 * Bengali strategy
 *   * Names/nicknames are TRANSLITERATED (Rahul -> রাহুল), never translated, so a
 *     name never turns into its dictionary meaning.
 *   * Addresses use Google Cloud Translation when GOOGLE_TRANSLATE_API_KEY is
 *     configured (same service the website uses), otherwise transliteration.
 *   * The API key lives ONLY in the server environment — never in the app.
 */
'use strict';

const TIMEOUT_MS = 6000;
const TTL_MS = 24 * 60 * 60 * 1000;
const MAX_CACHE = 3000;

const cache = new Map();
const cacheGet = (k) => {
    const hit = cache.get(k);
    if (!hit) return undefined;
    if (Date.now() - hit.t > TTL_MS) { cache.delete(k); return undefined; }
    return hit.v;
};
const cacheSet = (k, v) => {
    if (cache.size >= MAX_CACHE) cache.delete(cache.keys().next().value);
    cache.set(k, { v, t: Date.now() });
    return v;
};

const hasBengali = (s) => /[ঀ-৿]/.test(s);
const decodeEntities = (s) => s
    .replace(/&#0?39;|&apos;/g, "'").replace(/&quot;/g, '"')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');

async function getJson(url, init = {}) {
    const res = await fetch(url, { ...init, signal: AbortSignal.timeout(TIMEOUT_MS) });
    if (!res.ok) return null;
    return res.json();
}

// ── Bengali ──────────────────────────────────────────────────────────────────
// Google Input Tools (phonetic transliteration). Splits at commas itself so
// punctuation survives.
async function transliterateChunk(text) {
    const url = new URL('https://inputtools.google.com/request');
    url.search = new URLSearchParams({
        text, itc: 'bn-t-i0-und', num: '1', cp: '0', cs: '1', ie: 'utf-8', oe: 'utf-8', app: 'lgp-stock',
    }).toString();
    const d = await getJson(url);
    if (!Array.isArray(d) || d[0] !== 'SUCCESS' || !Array.isArray(d[1])) return null;
    return d[1].map((seg) => (seg && seg[1] && seg[1][0]) || '').join(' ').replace(/\s+/g, ' ').trim();
}

async function transliterate(text) {
    const chunks = text.split(/[,\n]+/).map((c) => c.trim()).filter(Boolean).slice(0, 8);
    const out = await Promise.all(chunks.map(transliterateChunk));
    if (out.some((o) => !o)) return null;
    return decodeEntities(out.join(', '));
}

async function googleTranslate(text) {
    const key = process.env.GOOGLE_TRANSLATE_API_KEY;
    if (!key) return null;
    const d = await getJson(`https://translation.googleapis.com/language/translate/v2?key=${encodeURIComponent(key)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ q: text, source: 'en', target: 'bn', format: 'text' }),
    });
    const t = d && d.data && d.data.translations && d.data.translations[0] && d.data.translations[0].translatedText;
    return t ? decodeEntities(t) : null;
}

/**
 * @param {string} text  English text
 * @param {'name'|'address'} kind
 * @returns {Promise<string|null>} Bengali text, or null if unavailable
 */
async function toBengali(text, kind = 'name') {
    const t = String(text || '').trim();
    if (!t || t.length > 300) return null;
    if (hasBengali(t)) return t;            // already Bengali
    const key = `bn:${kind}:${t.toLowerCase()}`;
    const hit = cacheGet(key);
    if (hit !== undefined) return hit;
    try {
        let out = null;
        if (kind === 'address') out = await googleTranslate(t);
        if (!out) out = await transliterate(t);
        return out ? cacheSet(key, out) : null;   // failures are not cached
    } catch (_) {
        return null;
    }
}

// ── Pincode ──────────────────────────────────────────────────────────────────
async function pincode(pin) {
    const p = String(pin || '').trim();
    if (!/^[1-9]\d{5}$/.test(p)) return null;
    const key = `pin:${p}`;
    const hit = cacheGet(key);
    if (hit !== undefined) return hit;
    try {
        const d = await getJson(`https://api.postalpincode.in/pincode/${p}`);
        const row = Array.isArray(d) ? d[0] : null;
        if (!row || row.Status !== 'Success' || !row.PostOffice || !row.PostOffice.length) return null;
        const po = row.PostOffice;
        return cacheSet(key, {
            pincode: p,
            state: po[0].State || po[0].Circle || '',
            district: po[0].District || '',
            city: po[0].District || po[0].Division || '',
            areas: [...new Set(po.map((o) => o.Name).filter(Boolean))].slice(0, 12),
        });
    } catch (_) {
        return null;
    }
}

// "KOLKATA MAIN" -> "Kolkata Main"
const title = (v) => String(v || '').toLowerCase().replace(/(^|[\s(\-/])([a-z])/g, (_, sep, c) => sep + c.toUpperCase());

// ── IFSC ─────────────────────────────────────────────────────────────────────
async function ifsc(code) {
    const c = String(code || '').trim().toUpperCase();
    if (!/^[A-Z]{4}0[A-Z0-9]{6}$/.test(c)) return null;
    const key = `ifsc:${c}`;
    const hit = cacheGet(key);
    if (hit !== undefined) return hit;
    try {
        const d = await getJson(`https://ifsc.razorpay.com/${c}`);
        if (!d || !d.BANK) return null;
        return cacheSet(key, {
            ifsc: c, bank: d.BANK, branch: title(d.BRANCH), city: title(d.CITY), state: title(d.STATE),
            district: title(d.DISTRICT), address: d.ADDRESS || '',
        });
    } catch (_) {
        return null;
    }
}

module.exports = { toBengali, pincode, ifsc, hasBengali };
