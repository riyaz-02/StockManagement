'use strict';
const crypto = require('crypto');

/**
 * The address to rate-limit by. Normally req.ip. The website (PHP on another host) makes every staff login from ONE address,
 * so it may pass the visitor's address in X-Portal-Client-Ip, but only together with the shared secret X-Portal-Key
 * (env PORTAL_SHARED_KEY). Without the secret the header is ignored, so nobody can fake an address to dodge the limit.
 */
function trustedClientIp(req) {
    const key = process.env.PORTAL_SHARED_KEY || '';
    const sent = String(req.get('x-portal-key') || '');
    const ip = String(req.get('x-portal-client-ip') || '');
    if (key && sent.length === key.length && crypto.timingSafeEqual(Buffer.from(key), Buffer.from(sent)) && /^[0-9a-fA-F:.]{3,45}$/.test(ip)) return ip;
    return req.ip;
}

module.exports = { trustedClientIp };
