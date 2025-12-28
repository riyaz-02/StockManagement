const Item = require('../models/Item');
const Booking = require('../models/Booking');

// @desc    Scan barcode and get item details
// @route   POST /api/scan
// @access  Private
exports.scanBarcode = async (req, res) => {
    try {
        const { barcode } = req.body;

        if (!barcode) {
            return res.status(400).json({
                success: false,
                message: 'Please provide barcode'
            });
        }

        // Find item by barcode
        const item = await Item.findOne({ barcode })
            .populate('containerId', 'name type layoutType');

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found',
                data: { barcode }
            });
        }

        // Get booking info if item is booked
        let bookingInfo = null;
        if (item.status === 'booked') {
            bookingInfo = await Booking.findOne({
                itemId: item._id,
                status: 'active'
            });
        }

        res.status(200).json({
            success: true,
            message: 'Item found',
            data: {
                item,
                booking: bookingInfo
            }
        });
    } catch (error) {
        console.error('Scan barcode error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while scanning barcode'
        });
    }
};
