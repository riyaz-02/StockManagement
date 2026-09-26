// Tally helpers: box progress, what is left, pieces sold while the tally ran. Run: node scripts/tally-help.test.js
'use strict';
const assert = require('assert');
const H = require('../services/tallyHelp');
let n = 0;
const t = (name, fn) => { fn(); n++; console.log('  ok  ', name); };
const p = (o) => ({ id: String(Math.random()), scanned: false, gone: false, metalType: 'gold', weight: 1, containerId: 'b1', containerName: 'Box 1', ...o });

t('reconcile splits scanned / missing / sold since and works out the real expectation', () => {
    const r = H.reconcile([p({ scanned: true, weight: 2 }), p({ weight: 3 }), p({ gone: true, weight: 5 }), p({ metalType: 'silver', weight: 10 })]);
    assert.deepStrictEqual([r.scanned.length, r.missing.length, r.soldSince.length, r.expectedItems], [1, 2, 1, 3]);
    assert.strictEqual(r.expectedWeight.gold, 5);
    assert.strictEqual(r.soldWeight.gold, 5);
    assert.strictEqual(r.expectedWeight.silver, 10);
});

t('a piece sold since the start never counts as missing', () => {
    const r = H.reconcile([p({ scanned: true }), p({ gone: true })]);
    assert.strictEqual(r.missing.length, 0);
});

t('box progress: unfinished boxes come first, most left first, finished last, sold pieces ignored', () => {
    const b = H.boxProgress([
        p({ containerId: 'a', containerName: 'A', scanned: true }), p({ containerId: 'a', containerName: 'A', scanned: true }),
        p({ containerId: 'b', containerName: 'B' }), p({ containerId: 'b', containerName: 'B' }), p({ containerId: 'b', containerName: 'B', scanned: true }),
        p({ containerId: 'c', containerName: 'C' }), p({ containerId: 'c', containerName: 'C', gone: true }),
    ]);
    assert.deepStrictEqual(b.map((x) => [x.name, x.total, x.scanned, x.missing]), [['B', 3, 1, 2], ['C', 1, 0, 1], ['A', 2, 2, 0]]);
});

t('pieces in no box are grouped under "Not in any box"', () => {
    const b = H.boxProgress([p({ containerId: '', containerName: '' })]);
    assert.strictEqual(b[0].name, 'Not in any box');
});

t('empty input gives empty results, weights stay exact to the milligram', () => {
    const r = H.reconcile([]);
    assert.deepStrictEqual([r.expectedItems, r.missing.length], [0, 0]);
    assert.strictEqual(H.reconcile([p({ weight: 0.1 }), p({ weight: 0.2 })]).expectedWeight.gold, 0.3);
});

console.log(`\n${n} passed`);
