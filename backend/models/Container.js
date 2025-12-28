const mongoose = require('mongoose');

const slotSchema = new mongoose.Schema({
    slotNumber: {
        type: Number,
        required: true
    },
    itemId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Item',
        default: null
    },
    reserved: {
        type: Boolean,
        default: false
    }
}, { _id: false });

const containerSchema = new mongoose.Schema({
    name: {
        type: String,
        required: [true, 'Container name is required'],
        trim: true
    },
    type: {
        type: String,
        required: true
    },
    allowedItemTypes: [{
        type: String
    }],
    capacity: {
        type: Number,
        required: [true, 'Capacity is required'],
        min: 1
    },
    weightCategory: {
        type: String,
        default: 'mixed'
    },
    layoutType: {
        type: String,
        default: 'grid'
    },
    slots: [slotSchema],
    isActive: {
        type: Boolean,
        default: true
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

// Initialize slots when container is created
containerSchema.pre('save', function (next) {
    if (this.isNew && this.slots.length === 0) {
        for (let i = 1; i <= this.capacity; i++) {
            this.slots.push({
                slotNumber: i,
                itemId: null,
                reserved: false
            });
        }
    }
    this.updatedAt = Date.now();
    next();
});

// Virtual for occupied slots count
containerSchema.virtual('occupiedSlots').get(function () {
    if (!this.slots || !Array.isArray(this.slots)) return 0;
    return this.slots.filter(slot => slot.itemId !== null).length;
});

// Virtual for available slots count
containerSchema.virtual('availableSlots').get(function () {
    if (!this.slots || !Array.isArray(this.slots)) return 0;
    return this.slots.filter(slot => slot.itemId === null && !slot.reserved).length;
});

// Virtual for reserved slots count
containerSchema.virtual('reservedSlots').get(function () {
    if (!this.slots || !Array.isArray(this.slots)) return 0;
    return this.slots.filter(slot => slot.reserved).length;
});

// Enable virtuals in JSON
containerSchema.set('toJSON', { virtuals: true });
containerSchema.set('toObject', { virtuals: true });

module.exports = mongoose.model('Container', containerSchema);
