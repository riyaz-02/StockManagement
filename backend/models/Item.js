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
        enum: ['Light', 'Medium', 'Heavy'],
        default: 'Light'
    },
    huid: {
        type: String,
        trim: true,
        default: ''
    },
    images: [{
        type: String
    }],
    status: {
        type: String,
        enum: ['active', 'booked', 'repair', 'in_repair', 'temporarily_removed', 'sold'],
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
    slotReserved: {
        type: Boolean,
        default: false
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

// Index for faster queries
itemSchema.index({ status: 1, containerId: 1 });
itemSchema.index({ itemType: 1, metalType: 1 });

module.exports = mongoose.model('Item', itemSchema);
