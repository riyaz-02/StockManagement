const Item = require('../models/Item');
const Container = require('../models/Container');
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

// @desc    Lookup barcode - searches in both items and containers
// @route   GET /api/scan/lookup/:barcode
// @access  Private
exports.lookupBarcode = async (req, res) => {
    try {
        const { barcode } = req.params;

        if (!barcode) {
            return res.status(400).json({
                success: false,
                message: 'Barcode is required'
            });
        }

        console.log(`[SCAN LOOKUP] Searching for barcode: ${barcode}`);

        // First, check if it's an item
        const item = await Item.findOne({ barcode })
            .populate('containerId', 'name type qrCode');

        if (item) {
            console.log(`[SCAN LOOKUP] Found item: ${item._id}`);
            return res.status(200).json({
                success: true,
                type: 'item',
                data: item
            });
        }

        // If not an item, check if it's a container
        const container = await Container.findOne({ qrCode: barcode });

        if (container) {
            console.log(`[SCAN LOOKUP] Found container: ${container._id}`);
            return res.status(200).json({
                success: true,
                type: 'container',
                data: container
            });
        }

        // Not found in either collection
        console.log(`[SCAN LOOKUP] Barcode not found: ${barcode}`);
        return res.status(404).json({
            success: false,
            message: 'Barcode not found'
        });

    } catch (error) {
        console.error('[SCAN LOOKUP] Error:', error);
        return res.status(500).json({
            success: false,
            message: 'Server error while looking up barcode',
            error: error.message
        });
    }
};
