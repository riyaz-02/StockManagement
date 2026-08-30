const InventorySnapshot = require('../models/InventorySnapshot');

// @desc    Get all inventory snapshots (history list)
// @route   GET /api/inventory-snapshots
// @access  Private
exports.getInventorySnapshots = async (req, res) => {
    try {
        const snapshots = await InventorySnapshot.find()
            .populate('createdBy', 'name')
            .populate('tallySessionId', 'description date')
            .select('-items')
            .sort({ createdAt: -1 })
            .limit(100);

        res.status(200).json({
            success: true,
            count: snapshots.length,
            data: { snapshots }
        });
    } catch (error) {
        console.error('Get inventory snapshots error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching inventory snapshots'
        });
    }
};

// @desc    Get single inventory snapshot (with full item list)
// @route   GET /api/inventory-snapshots/:id
// @access  Private
exports.getInventorySnapshot = async (req, res) => {
    try {
        const snapshot = await InventorySnapshot.findById(req.params.id)
            .populate('createdBy', 'name')
            .populate('tallySessionId', 'description date');

        if (!snapshot) {
            return res.status(404).json({
                success: false,
                message: 'Inventory snapshot not found'
            });
        }

        res.status(200).json({
            success: true,
            data: { snapshot }
        });
    } catch (error) {
        console.error('Get inventory snapshot error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching inventory snapshot'
        });
    }
};
