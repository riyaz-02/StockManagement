const mongoose = require('mongoose');

const repairLogSchema = new mongoose.Schema({
    itemId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Item',
        required: [true, 'Item ID is required']
    },
    repairType: {
        type: String,
        required: [true, 'Repair type is required'],
        trim: true
    },
    sentTo: {
        type: String,
        required: [true, 'Repair vendor/workshop is required'],
        trim: true
    },
    sentDate: {
        type: Date,
        required: [true, 'Sent date is required'],
        default: Date.now
    },
    expectedReturnDate: {
        type: Date,
        required: [true, 'Expected return date is required']
    },
    actualReturnDate: {
        type: Date,
        default: null
    },
    slotReserved: {
        type: Boolean,
        required: true,
        default: false
    },
    originalContainerId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Container',
        default: null
    },
    originalSlotNumber: {
        type: Number,
        default: null
    },
    remarks: {
        type: String,
        trim: true,
        default: ''
    },
    status: {
        type: String,
        enum: ['in_repair', 'returned'],
        default: 'in_repair'
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
repairLogSchema.pre('save', function (next) {
    this.updatedAt = Date.now();
    next();
});

// Index for faster queries
repairLogSchema.index({ itemId: 1, status: 1 });
repairLogSchema.index({ status: 1, expectedReturnDate: 1 });

module.exports = mongoose.model('RepairLog', repairLogSchema);
