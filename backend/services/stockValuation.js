/**
 * stockValuation.js - the price of a piece of stock from its weights, following the Stock Setting rules
 * (services/stockRules.js). Pure and mirrored in flutter_app/lib/utils/stock_valuation.dart; the two are checked
 * against the same vectors (scripts/gen-valuation-vectors.js -> flutter_app/test/valuation_vectors.json).
 *
 *   net      = gross - less
 *   fine     = net x purity%                       (pure metal in the piece)
 *   finalFW  = net x (purity% + wastage%)          (fine + the shop's wastage)
 *   basis    = the weight a charge is worked out on: finalFine | fine | net | gross (chosen per charge in the rules)
 *   metal valuation = basis(valuation) x rate
 *   labour   = basis(labourCharges) x labourRate      making = basis(makingCharges) x makingRate
 *   customer wastage weight = basis(customerWastage: fine|net|gross) x cust wastage%   (shown, added to the metal when > 0)
 *   hallmark fee = charge per piece (x pieces) or per gram (x net), only for hallmarked / HUID pieces
 *   GST: 3% on metal + labour + making + stones (CGST 1.5 + SGST 1.5); the hallmark fee carries its own GST rates
 *        when the rule "hallmark GST" is on.
 */
'use strict';

const r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
const r3 = (n) => Math.round((Number(n) + Number.EPSILON) * 1000) / 1000;
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };

/** Purity as a percentage from what staff pick: 22K, 916, 91.6, 750, 999, 925, "916-22k", "silver925" ... */
function purityPercent(text) {
    const t = String(text || '').toLowerCase().replace(/\s/g, '');
    if (!t) return 0;
    const k = /(\d{1,2})k(?:t)?\b/.exec(t) || /-(\d{1,2})k/.exec(t);
    if (k) {
        const kt = Number(k[1]);
        return kt === 22 ? 91.6 : kt === 24 ? 99.9 : r2((kt / 24) * 100);
    }
    const n = /(\d+(?:\.\d+)?)/.exec(t);
    if (!n) return 0;
    const v = Number(n[1]);
    if (v > 100) return r2(v / 10);          // 916 -> 91.6, 999 -> 99.9, 925 -> 92.5
    return v;
}

function computeStock(i, rules) {
    const R = rules || {};
    const add = R.addStock || {};
    const hm = R.hallmark || { charge: 45, type: 'perPiece', cgst: 9, sgst: 9, igst: 18 };
    const gross = Math.max(0, num(i.gross));
    const less = Math.max(0, num(i.less));
    const net = i.net !== undefined && i.net !== null && i.net !== '' ? Math.max(0, num(i.net)) : Math.max(0, gross - less);
    const p = i.purityPct !== undefined && i.purityPct !== null && i.purityPct !== '' ? num(i.purityPct) : purityPercent(i.purity);
    const w = Math.max(0, num(i.wastage));
    const fine = net * (p / 100);
    const finalFine = net * ((p + w) / 100);
    const basis = { finalFine, fine, net, gross: gross > 0 ? gross : net };
    const pick = (b) => basis[b] !== undefined ? basis[b] : net;

    const custBasis = pick(add.customerWastage || 'fine');
    const custWastageWt = custBasis * (Math.max(0, num(i.custWastage)) / 100);
    const valuationWt = pick(add.valuation || 'finalFine') + custWastageWt;
    const metal = valuationWt * Math.max(0, num(i.rate));
    const labour = pick(add.labourCharges || 'net') * Math.max(0, num(i.labourRate));
    const making = pick(add.makingCharges || 'net') * Math.max(0, num(i.makingRate));
    const stones = Math.max(0, num(i.stoneValue));

    const pieces = Math.max(1, Math.floor(num(i.pieces) || 1));
    const certified = i.certification === 'hallmarked' || i.certification === 'huid';
    const hallmark = certified ? (hm.type === 'perGram' ? net * num(hm.charge) : pieces * num(hm.charge)) : 0;

    const taxable = metal + labour + making + stones;                    // the 3% part
    const goodsGst = taxable * 0.03;
    const hallmarkGstOn = add.hallmarkGst !== false;
    const hallmarkGst = hallmarkOn(hallmarkGstOn, hallmark, hm, !!i.interstate);
    const totalTaxable = taxable + hallmark;
    const totalGst = goodsGst + hallmarkGst;
    return {
        net: r3(net), purityPct: r2(p), fine: r3(fine), finalFine: r3(finalFine), custWastageWt: r3(custWastageWt), valuationWt: r3(valuationWt),
        metalValuation: r2(metal), labourTotal: r2(labour), makingTotal: r2(making), stoneValuation: r2(stones), hallmarkCharge: r2(hallmark),
        taxable: r2(totalTaxable), goodsGst: r2(goodsGst), hallmarkGst: r2(hallmarkGst), totalGst: r2(totalGst), finalPrice: r2(totalTaxable + totalGst),
        // what billing pre-fills as "making": labour + making
        makingForBilling: r2(labour + making),
    };
}

function hallmarkOn(on, fee, hm, interstate) {
    if (!on || fee <= 0) return 0;
    const rate = interstate ? num(hm.igst) : num(hm.cgst) + num(hm.sgst);
    return fee * (rate / 100);
}

/**
 * Price of a PURCHASE (metal bought from a supplier) with the Purchase rules:
 *   wastage weight = basis(purchase.wastage: fine | net | gross) x wastage%      final fine = fine + wastage weight
 *   metal = basis(purchase.finalValuation) x rate     labour = basis(purchase.labourCharges) x labour rate
 *   hallmark fee as in computeStock (per piece / per gram); taxable = metal + labour + hallmark; goodsTaxable = metal + labour
 *   (the 3% purchase GST base) and hallmarkGst = GST on the fee at the hallmark rates when the rule purchase.hallmarkGst is on
 */
function computePurchase(i, rules) {
    const R = rules || {};
    const pr = R.purchase || {};
    const hm = R.hallmark || { charge: 45, type: 'perPiece', cgst: 9, sgst: 9, igst: 18 };
    const gross = Math.max(0, num(i.gross));
    const less = Math.max(0, num(i.less));
    const net = i.net !== undefined && i.net !== null && i.net !== '' ? Math.max(0, num(i.net)) : Math.max(0, gross - less);
    const p = i.purityPct !== undefined && i.purityPct !== null && i.purityPct !== '' ? num(i.purityPct) : purityPercent(i.purity);
    const fine = net * (p / 100);
    const grossW = gross > 0 ? gross : net;
    const wBasis = { fine, net, gross: grossW }[pr.wastage || 'net'];
    const wastageWt = (wBasis === undefined ? net : wBasis) * (Math.max(0, num(i.wastage)) / 100);
    const finalFine = fine + wastageWt;
    const basis = { finalFine, fine, net, gross: grossW };
    const pick = (b) => (basis[b] !== undefined ? basis[b] : net);
    const valuationWt = pick(pr.finalValuation || 'net');
    const metal = valuationWt * Math.max(0, num(i.rate));
    const labour = pick(pr.labourCharges || 'fine') * Math.max(0, num(i.labourRate));
    const pieces = Math.max(1, Math.floor(num(i.pieces) || 1));
    const certified = i.certification === 'hallmarked' || i.certification === 'huid';
    const hallmark = certified ? (hm.type === 'perGram' ? net * num(hm.charge) : pieces * num(hm.charge)) : 0;
    return {
        net: r3(net), purityPct: r2(p), fine: r3(fine), wastageWt: r3(wastageWt), finalFine: r3(finalFine), valuationWt: r3(valuationWt),
        metalValuation: r2(metal), labourTotal: r2(labour), hallmarkCharge: r2(hallmark), taxable: r2(metal + labour + hallmark),
        // the goods carry the purchase GST (3%); the hallmark fee is a separate service with its own GST when the rule is on
        goodsTaxable: r2(metal + labour), hallmarkGst: r2(hallmarkOn(pr.hallmarkGst !== false, hallmark, hm, !!i.interstate)),
    };
}

/**
 * Value of OLD METAL / URD received from a customer, or RAW metal bought (Stock Setting > Old Metal rules).
 *   fine = net x purity%          final fine = net x (purity% - deduction%)   (melting / testing loss comes off the purity)
 *   valuation weight = basis(oldMetal.receivedValuation | oldMetal.rawMetalPurchaseValuation); amount = weight x rate
 *   kind 'old' = received from a customer; 'raw' = bought for stock
 */
function computeOldMetal(i, rules) {
    const R = rules || {};
    const om = R.oldMetal || {};
    const gross = Math.max(0, num(i.gross));
    const less = Math.max(0, num(i.less));
    const net = i.net !== undefined && i.net !== null && i.net !== '' ? Math.max(0, num(i.net)) : Math.max(0, gross - less);
    const p = i.purityPct !== undefined && i.purityPct !== null && i.purityPct !== '' ? num(i.purityPct) : purityPercent(i.purity);
    const d = Math.max(0, num(i.deduction));
    const fine = net * (p / 100);
    const finalFine = net * (Math.max(0, p - d) / 100);
    const grossW = gross > 0 ? gross : net;
    const basis = { finalFine, fine, net, gross: grossW };
    const b = i.kind === 'raw' ? (om.rawMetalPurchaseValuation || 'net') : (om.receivedValuation || 'fine');
    const wt = basis[b] !== undefined ? basis[b] : net;
    const amount = wt * Math.max(0, num(i.rate));
    return { net: r3(net), purityPct: r2(p), fine: r3(fine), finalFine: r3(finalFine), valuationWt: r3(wt), basis: b, amount: r2(amount) };
}

module.exports = { purityPercent, computeStock, computePurchase, computeOldMetal };
