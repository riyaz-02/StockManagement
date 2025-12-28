const mongoose = require('mongoose');

const tallySessionSchema = new mongoose.Schema({
    date: {
        type: Date,
        required: true,
        default: Date.now
    },
    description: {
        type: String,
        trim: true,
        default: ''
    },
    scannedItemIds: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Item'
    }],
    totalScannedWeight: {
        type: Number,
        default: 0
    },
    expectedTotalWeight: {
        type: Number,
        default: 0
    },
    weightByMetal: {
        gold: { type: Number, default: 0 },
        silver: { type: Number, default: 0 },
        platinum: { type: Number, default: 0 },
        mixed: { type: Number, default: 0 }
    },
    mismatchDetected: {
        type: Boolean,
        default: false
    },
    missingItems: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Item'
    }],
    extraItems: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Item'
    }],
    excludedItems: [{
        itemId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Item'
        },
        reason: {
            type: String,
            enum: ['in_repair', 'temporarily_removed', 'sold']
        }
    }],
    status: {
        type: String,
        enum: ['in_progress', 'locked'],
        default: 'in_progress'
    },
    createdBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    lockedAt: {
        type: Date,
        default: null
    },
    createdAt: {
        type: Date,
        default: Date.now
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
});

// Update timestamp on save
tallySessionSchema.pre('save', function (next) {
    this.updatedAt = Date.now();
    next();
});

// Method to calculate weight mismatch
tallySessionSchema.methods.calculateMismatch = function () {
    const difference = Math.abs(this.totalScannedWeight - this.expectedTotalWeight);
    this.mismatchDetected = difference > 0.01; // Tolerance of 0.01 grams
    return difference;
};

// Index for faster queries
tallySessionSchema.index({ status: 1, createdAt: -1 });
tallySessionSchema.index({ createdBy: 1, date: -1 });

module.exports = mongoose.model('TallySession', tallySessionSchema);
