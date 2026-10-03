process.env.PORTAL_SHARED_KEY = 'k'.repeat(40);
const { trustedClientIp } = require('../utils/clientIp');
const mk = (h, ip = '1.1.1.1') => ({ ip, get: (n) => h[n.toLowerCase()] });
const a = trustedClientIp(mk({ 'x-portal-key': 'k'.repeat(40), 'x-portal-client-ip': '9.9.9.9' }));
const b = trustedClientIp(mk({ 'x-portal-key': 'wrong'.padEnd(40, 'x'), 'x-portal-client-ip': '9.9.9.9' }));
const c = trustedClientIp(mk({ 'x-portal-client-ip': '9.9.9.9' }));
console.log(a === '9.9.9.9' && b === '1.1.1.1' && c === '1.1.1.1' ? 'clientIp ok' : 'clientIp FAIL ' + [a, b, c]);
