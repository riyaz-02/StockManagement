/**
 * DirectoryParty.js — suppliers and karigars (same shape, two collections).
 *
 * These are NEW collections owned by this app (prefixed `app_` so they can
 * never collide with legacy web-admin collections). No login/password is
 * stored here — that was in the legacy form but is not needed.
 */
const mongoose = require('mongoose');

const balance = { amount: { type: Number, default: 0 }, type: { type: String, enum: ['credit', 'debit'], default: 'credit' } };

const schema = new mongoose.Schema(
    {
        branchId: { type: String, default: 'main' },
        branchName: { type: String, default: 'Main branch' },
        partyType: { type: String, trim: true },        // e.g. Wholesaler, Karigar
        firmName: { type: String, trim: true },
        firstName: { type: String, required: true, trim: true },
        lastName: { type: String, trim: true },
        fatherName: { type: String, trim: true },
        gender: { type: String, enum: ['M', 'F', ''], default: 'M' },
        mobile: { type: String, required: true, trim: true },
        phone: { type: String, trim: true },
        email: { type: String, trim: true },
        reference: { type: String, trim: true },
        address: { type: String, trim: true },
        city: { type: String, trim: true },
        state: { type: String, trim: true },
        country: { type: String, trim: true, default: 'India' },
        pincode: { type: String, trim: true },
        businessName: { type: String, trim: true },
        gstNo: { type: String, trim: true, uppercase: true },
        panNo: { type: String, trim: true, uppercase: true },
        aadharNo: { type: String, trim: true },
        taxNo: { type: String, trim: true },
        bank: {
            name: String, accountName: String, accountNo: String, ifsc: { type: String, uppercase: true },
        },
        nominee: { name: String, relation: String },
        opening: {
            date: Date,
            cash: balance,
            gold: { weight: { type: Number, default: 0 }, unit: { type: String, default: 'gram' }, type: { type: String, default: 'credit' } },
            silver: { weight: { type: Number, default: 0 }, unit: { type: String, default: 'gram' }, type: { type: String, default: 'credit' } },
        },
        updatedBy: { type: String },
        updatedByName: { type: String },
        createdBy: { type: String },
        createdByName: { type: String },
    },
    { versionKey: false, timestamps: true, autoIndex: false, autoCreate: false }
);

module.exports = {
    supplier: (conn) => conn.models.DirectorySupplier || conn.model('DirectorySupplier', schema, 'app_suppliers'),
    karigar: (conn) => conn.models.DirectoryKarigar || conn.model('DirectoryKarigar', schema, 'app_karigars'),
};
