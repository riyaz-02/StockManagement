const mongoose = require('mongoose');

const itemSchema = new mongoose.Schema({
    barcode: {
        type: String,
        required: [true, 'Barcode is required'],
        unique: true,
        trim: true,
        index: true
    },
    name: {
        type: String,
        required: [true, 'Item name is required'],
        trim: true
    },
    description: {
        type: String,
        trim: true,
        default: ''
    },
    itemType: {
        type: String,
        required: [true, 'Item type is required']
    },
    metalType: {
        type: String,
        required: [true, 'Metal type is required']
    },
    purity: {
        type: String,
        required: [true, 'Purity is required']
    },
    netWeight: {
        type: Number,
        required: [true, 'Net weight is required'],
        min: 0
    },
    weightCategory: {
        type: String,
        enum: ['Light', 'Medium', 'Heavy', 'Mixed'],
        default: 'Light'
    },
    certificationType: {
        type: String,
        enum: ['none', 'hallmarked', 'huid'],
        default: 'none'
    },
    huidNumber: {
        type: String,
        trim: true,
        default: null,
        sparse: true, // Allow multiple null values, but unique non-null values
        index: true
    },
    // Deprecated: kept for backward compatibility with old data
    huid: {
        type: String,
        trim: true
        // No default - won't be saved in new items
    },
    images: [{
        type: String
    }],
    status: {
        type: String,
        enum: ['active', 'booked', 'repair', 'in_repair', 'temporarily_removed', 'sold', 'deleted', 'UNDER_REPAIR', 'WITH_CUSTOMER', 'WITH_AGENT', 'no_sell', 'action_needed'],
        default: 'active',
        index: true
    },
    containerId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Container',
        default: null
    },
    slotNumber: {
        type: Number,
        default: null
    },
    numberOfPieces: {
        type: Number,
        default: 1,
        min: [1, 'Number of pieces must be at least 1']
    },
    slotReserved: {
        type: Boolean,
        default: false
    },
    // Tag printing tracking
    tagsPrinted: {
        type: Boolean,
        default: false
    },
    lastTagPrintedAt: {
        type: Date,
        default: null
    },
    tagPrintCount: {
        type: Number,
        default: 0,
        min: 0
    },
    lastPrintedBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null
    },
    // Optional detail used by billing (all default to "not set", so existing items are untouched)
    grossWeight: { type: Number, default: null, min: 0 },      // g, piece with stones / other metal
    lessWeight: { type: Number, default: null, min: 0 },       // g, stones / dust / other metal (gross - net)
    stoneValue: { type: Number, default: null, min: 0 },       // Rs, value of the stones in the piece
    stoneNote: { type: String, trim: true, default: '' },      // e.g. "Ruby 0.4ct, Pearl"
    makingCharge: { type: Number, default: null, min: 0 },     // Rs, usual making charge of this piece
    wastage: { type: Number, default: null, min: 0 },          // % the shop adds on the net weight (final purity = purity + wastage)
    custWastage: { type: Number, default: null, min: 0 },      // % customer wastage
    labourRate: { type: Number, default: null, min: 0 },       // Rs per unit of the labour basis (see Stock Setting)
    makingRate: { type: Number, default: null, min: 0 },       // Rs per unit of the making basis
    soldInvoice: { type: String, default: '' },                // invoice the piece was sold on
    soldAt: { type: Date, default: null },
    soldBy: { type: String, default: '' },
    supplier: { type: String, trim: true, default: '' },
    size: { type: String, trim: true, default: '' },
    // Weight accuracy and verification tracking
    weightAccuracy: {
        type: String,
        enum: ['exact', 'approx', 'bulk'],
        required: true,
        default: 'exact'
    },
    lastVerifiedWeight: {
        type: Number,
        default: null
    },
    lastVerifiedAt: {
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
itemSchema.pre('save', function (next) {
    this.updatedAt = Date.now();
    next();
});

// Method to check if item should be counted in stock
itemSchema.methods.isInStock = function () {
    return ['active', 'booked'].includes(this.status);
};

// Method to check if item should be counted in tally
itemSchema.methods.isInTally = function () {
    return ['active', 'booked'].includes(this.status);
};

// Static method to get total weight by status
itemSchema.statics.getTotalWeight = async function (filters = {}) {
    const pipeline = [
        { $match: filters },
        {
            $group: {
                _id: '$metalType',
                totalWeight: { $sum: '$netWeight' },
                count: { $sum: 1 }
            }
        }
    ];

    return await this.aggregate(pipeline);
};


// Comprehensive indexes for faster queries
// Note: barcode and status already have index:true in schema definition above
itemSchema.index({ status: 1, containerId: 1 });
itemSchema.index({ itemType: 1, metalType: 1 });
itemSchema.index({ metalType: 1, status: 1 }); // For reports and filtering
itemSchema.index({ containerId: 1, slotNumber: 1 }); // For container views
itemSchema.index({ createdAt: -1 }); // For sorting by date
itemSchema.index({ status: 1, createdAt: -1 }); // For filtered lists

itemSchema.plugin(require('../utils/branchScope').branchPlugin);
module.exports = mongoose.model('Item', itemSchema);
