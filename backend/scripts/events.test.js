// Who may see an event (services/events.js visible) and the one-time tickets. Run: node scripts/events.test.js
'use strict';
const assert = require('assert');
process.env.LGP_TEST = '1';
const E = require('../services/events');
let n = 0;
const t = (name, fn) => { fn(); n++; console.log('  ok  ', name); };
const ev = (o = {}) => ({ branchId: 'all', audience: { roles: [], userIds: [] }, ...o });
const admin = { id: 'a1', role: 'admin', restrict: null };
const staffMain = { id: 's1', role: 'staff', restrict: ['main'] };
const staffMum = { id: 's2', role: 'staff', restrict: ['mum'] };

t('an event for everyone is seen by everyone', () => {
    for (const v of [admin, staffMain, staffMum]) assert.strictEqual(E.visible(ev(), v), true);
});
t('a branch event is seen by that branch and by people who see every branch, not by another branch', () => {
    const e = ev({ branchId: 'main' });
    assert.deepStrictEqual([E.visible(e, admin), E.visible(e, staffMain), E.visible(e, staffMum)], [true, true, false]);
});
t('an event for one role is seen only by that role', () => {
    const e = ev({ audience: { roles: ['staff'], userIds: [] } });
    assert.deepStrictEqual([E.visible(e, staffMain), E.visible(e, admin)], [true, false]);
});
t('an event for one person is seen only by that person', () => {
    const e = ev({ audience: { roles: [], userIds: ['s2'] } });
    assert.deepStrictEqual([E.visible(e, staffMum), E.visible(e, staffMain), E.visible(e, admin)], [true, false, false]);
});
t('branch and audience both have to match', () => {
    const e = ev({ branchId: 'mum', audience: { roles: ['staff'], userIds: [] } });
    assert.deepStrictEqual([E.visible(e, staffMum), E.visible(e, staffMain)], [true, false]);
});
t('an event with no branch is filed under main', () => {
    for (const branchId of [undefined, '']) {
        assert.strictEqual(E.visible({ branchId, audience: {} }, staffMain), true);
        assert.strictEqual(E.visible({ branchId, audience: {} }, staffMum), false);
    }
});
t('a ticket works once', () => {
    const tk = E.issueTicket(staffMain);
    assert.deepStrictEqual(E.consumeTicket(tk), staffMain);
    assert.strictEqual(E.consumeTicket(tk), null);
});
t('an unknown or empty ticket is refused', () => {
    assert.strictEqual(E.consumeTicket('nope'), null);
    assert.strictEqual(E.consumeTicket(''), null);
    assert.strictEqual(E.consumeTicket(undefined), null);
});
t('the wire form carries only what a client needs', () => {
    const w = E.wire({ seq: 7, type: 'rate.changed', module: '', data: { gold: 1 }, actorName: 'Admin', at: new Date(0), audience: { roles: ['x'] }, actorId: 'secret' });
    assert.deepStrictEqual(Object.keys(w).sort(), ['at', 'by', 'data', 'module', 'seq', 'type']);
});

console.log(`\n${n} passed`);
process.exit(0);
