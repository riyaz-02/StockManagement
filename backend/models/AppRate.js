const mongoose = require('mongoose');

// Today's metal rates, set once by the shop and used as the default on every bill and form (one document, key "main").
// gold / silver = rupees per gram, as the bills use them. `history` keeps the last changes (who, when, from what).
const schema = new mongoose.Schema(
    {
        key: { type: String, default: 'main', unique: true },
        gold: { type: Number, default: 0 },
        silver: { type: Number, default: 0 },
        updatedByName: String,
        history: { type: [{ at: Date, gold: Number, silver: Number, by: String }], default: [] },
    },
    { collection: 'app_rates', timestamps: true, versionKey: false }
);
module.exports = mongoose.models.AppRate || mongoose.model('AppRate', schema);
