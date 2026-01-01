const mongoose = require('mongoose');

const bookingSchema = new mongoose.Schema({
    itemId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Item',
        required: [true, 'Item ID is required']
    },
    customerId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Customer'
    },
    customerName: {
        type: String,
        required: [true, 'Customer name is required'],
        trim: true
    },
    mobile: {
        type: String,
        required: [true, 'Mobile number is required'],
        trim: true
    },
    bookingDate: {
        type: Date,
        required: true,
        default: Date.now
    },
    expiryDate: {
        type: Date,
        required: false
    },
    advanceAmount: {
        type: Number,
        default: 0,
        min: 0
    },
    remarks: {
        type: String,
        trim: true,
        default: ''
    },
    status: {
        type: String,
        enum: ['active', 'completed', 'cancelled', 'manufacturing'],
        default: 'active'
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
bookingSchema.pre('save', function (next) {
    this.updatedAt = Date.now();
    next();
});

// Index for faster queries
bookingSchema.index({ itemId: 1, status: 1 });
bookingSchema.index({ mobile: 1 });
bookingSchema.index({ bookingDate: -1 });

module.exports = mongoose.model('Booking', bookingSchema);
