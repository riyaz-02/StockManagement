const mongoose = require('mongoose');

const tallySessionSchema = new mongoose.Schema({
    // Basic Info
    date: {
        type: Date,
        required: true,
        default: Date.now
    },
    description: {
        type: String,
        trim: true,
        required: [true, 'Tally description is required']
    },
    createdBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },

    // Status
    status: {
        type: String,
        enum: ['active', 'locked', 'force_locked'],
        default: 'active'
    },

    // Initial Setup (Locked after creation)
    expectedItems: {
        type: Number,
        required: [true, 'Expected items count is required'],
        min: 0
    },
    expectedContainers: {
        type: Number,
        required: [true, 'Expected containers count is required'],
        min: 0
    },

    // Legacy fields (keep for backward compatibility)
    expectedGoldWeight: {
        type: Number,
        default: 0
    },
    expectedSilverWeight: {
        type: Number,
        default: 0
    },
    scannedGoldWeight: {
        type: Number,
        default: 0
    },
    scannedSilverWeight: {
        type: Number,
        default: 0
    },

    // NEW: Dynamic Metal Types Data
    metalData: [{
        metalType: {
            type: String,
            required: true
        },
        expectedWeight: {
            type: Number,
            default: 0
        },
        expectedItemCount: {
            type: Number,
            default: 0
        },
        scannedWeight: {
            type: Number,
            default: 0
        },
        scannedItemCount: {
            type: Number,
            default: 0
        }
    }],

    // Real-time Counters
    scannedItemsCount: {
        type: Number,
        default: 0
    },
    outOfStockCount: {
        type: Number,
        default: 0
    },

    // NEW: All Items with Scan Status
    items: [{
        itemId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Item',
            required: true
        },
        barcode: String,
        metalType: String,
        weight: Number,
        isScanned: {
            type: Boolean,
            default: false
        },
        scannedAt: Date,
        scannedBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        status: {
            type: String,
            enum: ['in_stock', 'out_of_stock', 'active', 'booked', 'wishlisted', 'removed'],
            default: 'in_stock'
        }
    }],

    // Scanned Items Array (Simple IDs for quick lookup)
    scannedItemIds: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Item'
    }],

    // Detailed Scan Records
    scannedItemDetails: [{
        itemId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Item',
            required: true
        },
        scannedAt: {
            type: Date,
            default: Date.now
        },
        scannedBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        status: {
            type: String,
            enum: ['in_stock', 'out_of_stock'],
            default: 'in_stock'
        },
        weight: {
            type: Number,
            default: 0
        },
        metalType: {
            type: String
        }
    }],

    // Legacy fields (keep for backward compatibility)
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
            enum: ['in_repair', 'temporarily_removed', 'sold', 'with_customer', 'with_agent']
        }
    }],

    // Lock Details
    lockedAt: {
        type: Date,
        default: null
    },
    lockedBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null
    },
    lockRemarks: {
        type: String,
        trim: true,
        default: ''
    },
    isForceLocked: {
        type: Boolean,
        default: false
    },

    // Inventory Snapshot
    inventoryUpdated: {
        type: Boolean,
        default: false
    },
    inventoryUpdatedAt: {
        type: Date,
        default: null
    },
    inventorySnapshotId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'InventorySnapshot',
        default: null
    },

    // Timestamps
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
    const goldDiff = Math.abs(this.scannedGoldWeight - this.expectedGoldWeight);
    const silverDiff = Math.abs(this.scannedSilverWeight - this.expectedSilverWeight);
    const totalDiff = goldDiff + silverDiff;

    this.mismatchDetected = totalDiff > 0.01; // Tolerance of 0.01 grams
    return {
        goldDifference: goldDiff,
        silverDifference: silverDiff,
        totalDifference: totalDiff,
        mismatchDetected: this.mismatchDetected
    };
};

// Method to check if item already scanned
tallySessionSchema.methods.isItemScanned = function (itemId) {
    return this.scannedItemIds.some(id => id.toString() === itemId.toString());
};

// Method to get progress percentage
tallySessionSchema.methods.getProgress = function () {
    if (this.expectedItems === 0) return 0;
    return Math.round((this.scannedItemsCount / this.expectedItems) * 100);
};

// Method to get metal data by type
tallySessionSchema.methods.getMetalData = function (metalType) {
    return this.metalData.find(m => m.metalType.toLowerCase() === metalType.toLowerCase());
};

// Index for faster queries
tallySessionSchema.index({ status: 1, createdAt: -1 });
tallySessionSchema.index({ createdBy: 1, date: -1 });
tallySessionSchema.index({ 'scannedItemIds': 1 });
tallySessionSchema.index({ 'items.itemId': 1 });

module.exports = mongoose.model('TallySession', tallySessionSchema);
