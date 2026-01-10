const Item = require('../models/Item');

// Get all items for tag printing
exports.getItemsForTagPrinting = async (req, res) => {
    try {
        const items = await Item.find({
            status: { $in: ['active', 'booked', 'in_stock'] }
        })
            .populate('containerId', 'name qrCode')
            .populate('lastPrintedBy', 'name')
            .sort({ name: 1 });

        res.status(200).json({
            success: true,
            count: items.length,
            items
        });
    } catch (error) {
        console.error('Error fetching items for tag printing:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch items',
            error: error.message
        });
    }
};

// Record tag print event
exports.recordTagPrint = async (req, res) => {
    try {
        const { itemIds } = req.body;
        const userId = req.user._id;

        if (!itemIds || !Array.isArray(itemIds) || itemIds.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'Item IDs array is required'
            });
        }

        const result = await Item.updateMany(
            { _id: { $in: itemIds } },
            {
                $set: {
                    tagsPrinted: true,
                    lastTagPrintedAt: new Date(),
                    lastPrintedBy: userId
                },
                $inc: { tagPrintCount: 1 }
            }
        );

        res.status(200).json({
            success: true,
            message: `Tag print recorded for ${result.modifiedCount} items`,
            modifiedCount: result.modifiedCount
        });
    } catch (error) {
        console.error('Error recording tag print:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to record tag print',
            error: error.message
        });
    }
};

// Get tag print history for an item
exports.getTagPrintHistory = async (req, res) => {
    try {
        const { itemId } = req.params;

        const item = await Item.findById(itemId)
            .populate('lastPrintedBy', 'name email')
            .select('barcode name tagsPrinted lastTagPrintedAt tagPrintCount lastPrintedBy');

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        res.status(200).json({
            success: true,
            history: {
                barcode: item.barcode,
                name: item.name,
                tagsPrinted: item.tagsPrinted,
                lastTagPrintedAt: item.lastTagPrintedAt,
                tagPrintCount: item.tagPrintCount,
                lastPrintedBy: item.lastPrintedBy
            }
        });
    } catch (error) {
        console.error('Error fetching tag print history:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch tag print history',
            error: error.message
        });
    }
};
