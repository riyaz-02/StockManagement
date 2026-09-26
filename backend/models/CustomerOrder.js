/**
 * CustomerOrder.js - a made-to-order piece a customer asks for, with an advance (collection app_orders). Branch-scoped.
 *
 * Life: new -> making -> ready -> delivered (billed) ; or cancelled (the advance is paid back).
 * No GST at this stage (an advance for goods carries none: the tax comes on the bill at delivery). The advance is real money
 * (it shows in the Day Book on the day it is taken) and on delivery it is credited on the bill as "Order Advance".
 */
const mongoose = require('mongoose');

const STATUSES = ['new', 'making', 'ready', 'delivered', 'cancelled'];

const schema = new mongoose.Schema(
    {
        number: { type: String, required: true, unique: true },            // ORD-0001 (branch prefix for other branches)
        requestId: { type: String, index: true, sparse: true, unique: true },
        date: { type: String, required: true, index: true },               // YYYY-MM-DD (India)
        customerId: { type: String, default: '' },
        customerName: { type: String, trim: true, required: true },
        customerMobile: { type: String, trim: true, default: '' },
        description: { type: String, trim: true, required: true },         // what to make: "Gold chain, 22K, 20 g, rope pattern"
        metalType: { type: String, default: 'gold' },
        purity: { type: String, default: '' },
        approxWeight: { type: Number, default: 0 },
        estimatedPrice: { type: Number, default: 0 },                      // what the customer was told (for reference)
        deliveryDate: { type: String, required: true, index: true },
        karigar: { type: String, trim: true, default: '' },                // who is making it
        note: { type: String, default: '' },
        advances: { type: [{ date: String, amount: Number, mode: String, byName: String, at: Date }], default: [] },
        advancePaid: { type: Number, default: 0 },                         // sum of the advances
        refunds: { type: [{ date: String, amount: Number, mode: String, reason: String, byName: String, at: Date }], default: [] },
        status: { type: String, enum: STATUSES, default: 'new', index: true },
        history: { type: [{ status: String, at: Date, byName: String }], default: [] },
        invoiceNumber: { type: String, default: '' },
        invoiceClaim: { type: String, default: '' },                       // set while a bill is being made from it
        createdBy: String,
        createdByName: String,
    },
    { collection: 'app_orders', timestamps: true }
);
schema.plugin(require('../utils/branchScope').branchPlugin);
const Model = mongoose.models.AppCustomerOrder || mongoose.model('AppCustomerOrder', schema);
module.exports = Model;
module.exports.STATUSES = STATUSES;
