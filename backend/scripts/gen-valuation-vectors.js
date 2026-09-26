// Generates flutter_app/test/valuation_vectors.json: random stock inputs + rules and what services/stockValuation.js says.
// The Dart mirror (lib/utils/stock_valuation.dart) is tested against the same file. Run after changing the engine.
'use strict';
const fs = require('fs');
const path = require('path');
const V = require('../services/stockValuation');
const Rules = require('../services/stockRules');

let seed = 7;
const rnd = () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const between = (a, b) => a + rnd() * (b - a);
const round = (n, d) => Math.round(n * 10 ** d) / 10 ** d;

const out = { purity: [], cases: [] };
for (const t of ['22K', '18K', '24K', '14K', '916', '750', '999', '925', '916-22k', '750-18k', '20kt', 'silver925', 'silver999', 'platinum950', 'hallmark-silver', '', 'x', '91.6', '22 K']) out.purity.push([t, V.purityPercent(t)]);
for (let n = 0; n < 80; n++) {
    const rules = Rules.defaults();
    rules.addStock.customerWastage = pick(['fine', 'net', 'gross']);
    rules.addStock.valuation = pick(['finalFine', 'fine', 'net', 'gross']);
    rules.addStock.makingCharges = pick(['finalFine', 'fine', 'net', 'gross']);
    rules.addStock.labourCharges = pick(['finalFine', 'fine', 'net', 'gross']);
    rules.addStock.hallmarkGst = pick([true, false]);
    rules.hallmark = { charge: pick([0, 45, 60, 12.5]), type: pick(['perPiece', 'perGram']), cgst: 9, sgst: 9, igst: 18 };
    const gross = pick([0, round(between(1, 60), 3)]);
    const less = gross ? round(between(0, gross * 0.2), 3) : 0;
    const input = {
        gross, less, net: gross ? undefined : round(between(1, 50), 3), purity: pick(['22K', '18K', '916', '750', '925', '24K', '']), wastage: pick([0, round(between(0, 12), 2)]),
        custWastage: pick([0, round(between(0, 6), 2)]), rate: round(between(90, 15000), 2), labourRate: pick([0, round(between(0, 500), 2)]), makingRate: pick([0, round(between(0, 800), 2)]),
        stoneValue: pick([0, round(between(0, 20000), 2)]), pieces: pick([1, 2, 5]), certification: pick(['none', 'hallmarked', 'huid']), interstate: pick([true, false]),
    };
    for (const k of Object.keys(input)) if (input[k] === undefined) delete input[k];
    out.cases.push({ input, rules, expect: V.computeStock(input, rules) });
}
out.purchase = [];
for (let n = 0; n < 60; n++) {
    const rules = Rules.defaults();
    rules.purchase.labourCharges = pick(['finalFine', 'fine', 'net', 'gross']);
    rules.purchase.wastage = pick(['fine', 'net', 'gross']);
    rules.purchase.finalValuation = pick(['finalFine', 'fine', 'net', 'gross']);
    rules.hallmark = { charge: pick([0, 45, 12.5]), type: pick(['perPiece', 'perGram']), cgst: 9, sgst: 9, igst: 18 };
    const gross = pick([0, round(between(1, 900), 3)]);
    const input = { gross, less: gross ? round(between(0, gross * 0.1), 3) : 0, net: gross ? undefined : round(between(1, 500), 3), purity: pick(['22K', '916', '999', '24K', '925', '18K']), wastage: pick([0, round(between(0, 10), 2)]), rate: round(between(90, 15000), 2), labourRate: pick([0, round(between(0, 300), 2)]), pieces: pick([1, 3]), certification: pick(['none', 'huid']), interstate: pick([false, true]) };
    for (const k of Object.keys(input)) if (input[k] === undefined) delete input[k];
    out.purchase.push({ input, rules, expect: V.computePurchase(input, rules) });
}
out.oldMetal = [];
for (let n = 0; n < 40; n++) {
    const rules = Rules.defaults();
    rules.oldMetal.receivedValuation = pick(['finalFine', 'fine', 'net', 'gross']);
    rules.oldMetal.rawMetalPurchaseValuation = pick(['finalFine', 'fine', 'net', 'gross']);
    const gross = pick([0, round(between(1, 300), 3)]);
    const input = { kind: pick(['old', 'raw']), gross, less: gross ? round(between(0, gross * 0.1), 3) : 0, net: gross ? undefined : round(between(1, 200), 3), purity: pick(['22K', '916', '999', '18K', '925', '']), deduction: pick([0, round(between(0, 8), 2)]), rate: round(between(90, 15000), 2) };
    for (const k of Object.keys(input)) if (input[k] === undefined) delete input[k];
    out.oldMetal.push({ input, rules, expect: V.computeOldMetal(input, rules) });
}
fs.writeFileSync(path.join(__dirname, '..', '..', 'flutter_app', 'test', 'valuation_vectors.json'), JSON.stringify(out));
console.log(`${out.cases.length} cases, ${out.purity.length} purity checks written`);
