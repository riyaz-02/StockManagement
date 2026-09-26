/**
 * LgpCustomer.js — the EXISTING production `customers` collection on the LGP
 * admin cluster (shopmanage db). Written by the legacy web admin.
 *
 * The directory API only reads from it and inserts new documents. It never
 * updates or deletes existing ones. Field names mirror the legacy documents
 * exactly (snake_case) so both systems stay compatible.
 */
const mongoose = require('mongoose');

const schema = new mongoose.Schema(
    {
        customer_name: { type: String, trim: true },
        customer_name_bengali: { type: String, default: '' },
        address: { type: String, trim: true, default: '' },
        address_bengali: { type: String, default: '' },
        whatsapp_no: { type: String, trim: true, default: '' },
        mobile_no: { type: String, trim: true, default: '' },
        mobile_no_3: { type: String, trim: true },
        mobile_no_4: { type: String, trim: true },
        email: { type: String, trim: true },
        gender: { type: String },
        nickname: { type: String, trim: true },
        reference_customer_id: { type: String },
        anniversaries: [{ _id: false, occasion: String, date: Date }],
        notification_type: { type: String, default: 'all' },
        updated_by: { type: String },
        updated_by_name: { type: String },
        created_by: { type: String },
        created_by_name: { type: String },
        created_at: { type: Date },
        updated_at: { type: Date },
        sl_no: { type: Number },
        is_deleted: { type: Boolean },
    },
    { collection: 'customers', versionKey: false, autoIndex: false, autoCreate: false }
);

module.exports = (conn) => conn.models.LgpCustomer || conn.model('LgpCustomer', schema);
