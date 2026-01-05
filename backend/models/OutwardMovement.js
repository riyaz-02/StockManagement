const mongoose = require('mongoose');

const outwardMovementSchema = new mongoose.Schema({
    itemId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Item',
        required: true,
        index: true
    },
    movementType: {
        type: String,
        enum: ['REPAIR', 'CUSTOMER_TRIAL', 'AGENT_CONSIGNMENT'],
        required: true
    },

    // Common Fields
    outDate: {
        type: Date,
        required: true,
        default: Date.now
    },
    grossWeight: {
        type: Number,
        required: true,
        min: 0
    },
    purity: {
        type: String,
        required: true
    },
    expectedReturnDate: {
        type: Date
    },
    remarks: {
        type: String,
        default: ''
    },
    photos: [{
        type: String
    }],

    // Repair/Maintenance Specific
    givenTo: {
        type: String // Karigar/Workshop name
    },
    repairType: {
        type: String // Polish, Resize, Stone, Other
    },
    estimatedWeightLoss: {
        type: Number,
        min: 0
    },
    jobCardNumber: {
        type: String
    },

    // Customer Trial Specific
    customerName: {
        type: String
    },
    customerMobile: {
        type: String,
        validate: {
            validator: function (v) {
                return !v || /^\d{10}$/.test(v);
            },
            message: 'Mobile number must be 10 digits'
        }
    },
    idProofType: {
        type: String,
        enum: ['Aadhaar', 'PAN', 'DL', 'Passport', 'Other', '']
    },

    // Agent/Shop Consignment Specific
    partyName: {
        type: String
    },
    partyType: {
        type: String,
        enum: ['SHOP', 'AGENT', 'WHOLESALER', '']
    },
    gstin: {
        type: String
    },
    expectedSettlementDate: {
        type: Date
    },
    consignmentType: {
        type: String,
        enum: ['Approval', 'Sale After Confirmation', '']
    },
    challanNumber: {
        type: String
    },

    // System Fields
    status: {
        type: String,
        enum: ['OUT', 'RETURNED', 'SETTLED'],
        default: 'OUT',
        index: true
    },
    previousItemStatus: {
        type: String,
        required: true
    },
    performedBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    performedByName: {
        type: String
    },
    returnDate: {
        type: Date
    },
    deviceId: {
        type: String
    },
    ipAddress: {
        type: String
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
outwardMovementSchema.pre('save', function (next) {
    this.updatedAt = Date.now();
    next();
});

// Index for faster queries
outwardMovementSchema.index({ itemId: 1, status: 1 });
outwardMovementSchema.index({ movementType: 1, status: 1 });
outwardMovementSchema.index({ createdAt: -1 });

module.exports = mongoose.model('OutwardMovement', outwardMovementSchema);
