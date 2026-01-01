const mongoose = require('mongoose');

const saleSchema = new mongoose.Schema({
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
    address: {
        type: String,
        trim: true
    },
    saleDate: {
        type: Date,
        default: Date.now
    },
    amount: {
        type: Number
    },
    createdAt: {
        type: Date,
        default: Date.now
    }
});

saleSchema.index({ itemId: 1 });
saleSchema.index({ mobile: 1 });
saleSchema.index({ saleDate: -1 });

module.exports = mongoose.model('Sale', saleSchema);
