const Item = require('../models/Item');
const Container = require('../models/Container');
const { nanoid } = require('nanoid');

// ... existing code ...

// @desc    Restore deleted item
// @route   PUT /api/items/:id/restore
// @access  Private
exports.restoreItem = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        if (item.status !== 'deleted') {
            return res.status(400).json({
                success: false,
                message: 'Item is not deleted'
            });
        }

        // Restore item to active status
        item.status = 'active';
        await item.save();

        res.status(200).json({
            success: true,
            message: 'Item restored successfully',
            data: { item }
        });
    } catch (error) {
        console.error('Restore item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while restoring item'
        });
    }
};

// @desc    Permanently delete item
// @route   DELETE /api/items/:id/permanent
// @access  Private/Admin
exports.permanentDeleteItem = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Permanently delete the item
        await Item.findByIdAndDelete(req.params.id);

        res.status(200).json({
            success: true,
            message: 'Item permanently deleted'
        });
    } catch (error) {
        console.error('Permanent delete item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while permanently deleting item'
        });
    }
};
