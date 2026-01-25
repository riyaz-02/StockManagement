const mongoose = require('mongoose');

const settingsSchema = new mongoose.Schema({
    category: {
        type: String,
        required: true,
        enum: ['item', 'container', 'tag'],
    },
    type: {
        type: String,
        required: true,
    },
    values: [{
        type: String,
        required: true,
    }],
    containerSettings: {
        maxCapacity: { type: Number, default: 100 },
        allowMixedMetals: { type: Boolean, default: false },
        requireSlotAssignment: { type: Boolean, default: true }
    },

    // Tag Printing Settings
    tagSettings: {
        // Tag size in mm (width x height)
        tagWidth: { type: Number, default: 50 },
        tagHeight: { type: Number, default: 30 },

        // Purity color mappings - array of { purity, color }
        purityColors: [{
            purity: { type: String, required: true },
            color: { type: String, required: true, default: '#FFD700' } // Default gold color
        }]
    },
    updatedBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
    },
}, {
    timestamps: true,
});

// Create compound index for category + type (unique combination)
settingsSchema.index({ category: 1, type: 1 }, { unique: true });

module.exports = mongoose.model('Settings', settingsSchema);
