const mongoose = require('mongoose');

const settingsSchema = new mongoose.Schema({
    category: {
        type: String,
        required: true,
        enum: ['item', 'container'],
    },
    type: {
        type: String,
        required: true,
    },
    values: [{
        type: String,
        required: true,
    }],
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
