/**
 * billingSeller.js — who is issuing the invoice, and the printed terms.
 *
 * Copied from the LIVE system (D:\LGPManagement, assets/templates/
 * invoice_template2.php) so an invoice printed from the app reads exactly like
 * one printed from the website. Priority: the GST configuration saved in the
 * app (Settings > GST) > environment overrides > these defaults.
 */
'use strict';

const DEFAULTS = {
    firmName: 'LALTU GUINEA PALACE',
    address: 'Siddheswari Appartment, M.G.M. Sarani, Bagbazzar, Chandannagar, Hooghly, West Bengal-712136',
    phone: '+91-9831292885, 7003067971, 7003322568, 7003555530',
    email: '',
    gstin: '19AKFPN3465R1ZB',
    stateCode: '19',
    state: 'West Bengal',
};

async function getSeller() {
    const s = {
        ...DEFAULTS,
        firmName: process.env.SELLER_NAME || DEFAULTS.firmName,
        address: process.env.SELLER_ADDRESS || DEFAULTS.address,
        phone: process.env.SELLER_PHONE || DEFAULTS.phone,
        email: process.env.SELLER_EMAIL || DEFAULTS.email,
        gstin: process.env.SELLER_GSTIN || DEFAULTS.gstin,
    };
    try {
        const { getShopmanageConnection } = require('../config/db');
        const cfg = await require('../models/GstConfig')(getShopmanageConnection()).findOne({ isActive: true }).lean();
        if (cfg) {
            if (cfg.firmName) s.firmName = cfg.firmName;
            if (cfg.gstin) { s.gstin = cfg.gstin; s.stateCode = cfg.stateCode || cfg.gstin.slice(0, 2); }
        }
    } catch (_) { /* no GST config yet: use the defaults */ }
    return s;
}

const TERMS = [
    'Items once sold may be accepted for return or exchange only in specific cases, subject to valid reasons and management approval.',
    'All disputes are subject to Chandannagar jurisdiction only.',
    'Our liability is limited to repair, replacement, or exchange of goods, as decided by the management.',
    'Purity of gold/silver is as mentioned at the time of sale and verified using appropriate methods.',
    'We are not responsible for any damage or loss occurring after the goods are delivered.',
    'Customized or special orders are non-returnable and non-refundable unless there is a manufacturing defect.',
];
const DECLARATION = 'We declare that this invoice shows the actual price of the goods described and all particulars are true and correct.';

// Same choices as the website's billing form.
const HSN_CODES = [
    { code: '7113', label: '7113 - Jewelry (Turnover < ₹1.5Cr)' },
    { code: '71131900', label: '71131900 - Gold Jewelry (Turnover > ₹1.5Cr)' },
    { code: '71131100', label: '71131100 - Silver Jewelry (Turnover > ₹1.5Cr)' },
    { code: '71132000', label: '71132000 - Base Metal Jewelry (Turnover > ₹1.5Cr)' },
    { code: '71171900', label: '71171900 - Imitation Jewelry (Turnover > ₹1.5Cr)' },
];
const TERMS_OF_DELIVERY = ['Ex-Showroom', 'Free Delivery', 'Customer Pickup', 'Home Delivery', 'Courier'];

module.exports = { getSeller, TERMS, DECLARATION, HSN_CODES, TERMS_OF_DELIVERY, DEFAULTS };
