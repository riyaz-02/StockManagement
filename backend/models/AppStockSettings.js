const mongoose = require('mongoose');

// One document (key "main") holding the Stock Setting parameters; see services/stockRules.js
const schema = new mongoose.Schema(
    { key: { type: String, default: 'main', unique: true }, addStock: Object, sellStock: Object, purchase: Object, oldMetal: Object, hallmark: Object, reconcile: Object, updatedBy: String, updatedByName: String },
    { collection: 'app_stock_settings', timestamps: true, versionKey: false, strict: false }
);
module.exports = mongoose.models.AppStockSettings || mongoose.model('AppStockSettings', schema);
