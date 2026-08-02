/**
 * BulkWeight.js — Admin-controlled bulk/untagged stock entries (shopmanage DB)
 *
 * Tracks gold/silver that cannot be barcoded:
 *   - Reserved gold
 *   - Raw material (melted/cast form)
 *   - In-process items
 *
 * These are combined with barcoded item weights to produce the
 * total stock figure shown on the Stock Dashboard.
 *
 * Admins can edit/delete entries daily. Each edit creates a new entry
 * or updates the existing one for that metalType+date.
 */

const mongoose = require('mongoose');

const bulkWeightSchema = new mongoose.Schema(
    {
        metalType: {
            type: String,
            required: [true, 'Metal type is required'],
            enum: ['gold', 'silver', 'platinum', 'other'],
            lowercase: true,
        },
        weightGrams: {
            type: Number,
            required: [true, 'Weight is required'],
            min: [0, 'Weight cannot be negative'],
        },
        description: {
            type: String,
            trim: true,
            required: [true, 'Description is required'],
            maxlength: [200, 'Description cannot exceed 200 characters'],
        },
        // Date this weight is applicable for (defaults to today IST)
        date: {
            type: Date,
            default: Date.now,
            index: true,
        },
        // Whether this entry is currently active (soft-disable instead of delete)
        isActive: {
            type: Boolean,
            default: true,
            index: true,
        },
        updatedBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
        },
        createdBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
            required: true,
        },
    },
    {
        timestamps: true,
        collection: 'bulk_weights',
    }
);

bulkWeightSchema.index({ metalType: 1, isActive: 1 });
bulkWeightSchema.index({ date: -1 });

module.exports = (connection) => connection.model('BulkWeight', bulkWeightSchema);
