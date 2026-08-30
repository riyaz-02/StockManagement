const mongoose = require('mongoose');

const snapshotItemSchema = new mongoose.Schema({
    itemId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Item',
        required: true
    },
    barcode: String,
    name: String,
    metalType: String,
    netWeight: Number,
    containerId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Container',
        default: null
    },
    containerName: {
        type: String,
        default: null
    },
    slotNumber: {
        type: Number,
        default: null
    },
    status: String
}, { _id: false });

const inventorySnapshotSchema = new mongoose.Schema({
    tallySessionId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'TallySession',
        required: true,
        index: true
    },
    date: {
        type: Date,
        required: true,
        default: Date.now
    },
    createdBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    totalItems: {
        type: Number,
        default: 0
    },
    totalContainers: {
        type: Number,
        default: 0
    },
    byMetal: [{
        metalType: {
            type: String,
            required: true
        },
        totalWeight: {
            type: Number,
            default: 0
        },
        itemCount: {
            type: Number,
            default: 0
        }
    }],
    items: [snapshotItemSchema],
    createdAt: {
        type: Date,
        default: Date.now
    }
});

inventorySnapshotSchema.index({ createdAt: -1 });

module.exports = mongoose.model('InventorySnapshot', inventorySnapshotSchema);
