const OutwardMovement = require('../models/OutwardMovement');
const Item = require('../models/Item');
const User = require('../models/User');
const moment = require('moment-timezone');

// @desc    Create outward movement
// @route   POST /api/outward-movements
// @access  Private
exports.createOutwardMovement = async (req, res) => {
    try {
        const {
            itemId,
            movementType,
            outDate,
            grossWeight,
            purity,
            expectedReturnDate,
            remarks,
            photos,
            // Repair specific
            givenTo,
            repairType,
            estimatedWeightLoss,
            jobCardNumber,
            // Customer trial specific
            customerName,
            customerMobile,
            idProofType,
            // Agent consignment specific
            partyName,
            partyType,
            gstin,
            expectedSettlementDate,
            consignmentType,
            challanNumber
        } = req.body;

        // Validate item exists
        const item = await Item.findById(itemId);
        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Check if item is available for movement
        if (!['active', 'booked'].includes(item.status)) {
            return res.status(400).json({
                success: false,
                message: `Item cannot be moved out. Current status: ${item.status}`
            });
        }

        // Validate required fields based on movement type
        if (movementType === 'REPAIR') {
            if (!givenTo) {
                return res.status(400).json({
                    success: false,
                    message: 'Given To (Karigar/Workshop) is required for repair'
                });
            }
        } else if (movementType === 'CUSTOMER_TRIAL') {
            if (!customerName || !customerMobile) {
                return res.status(400).json({
                    success: false,
                    message: 'Customer name and mobile are required for customer trial'
                });
            }
            // Validate mobile number
            if (!/^\d{10}$/.test(customerMobile)) {
                return res.status(400).json({
                    success: false,
                    message: 'Mobile number must be exactly 10 digits'
                });
            }
        } else if (movementType === 'AGENT_CONSIGNMENT') {
            if (!partyName || !partyType) {
                return res.status(400).json({
                    success: false,
                    message: 'Party name and type are required for agent consignment'
                });
            }
        }

        // Validate common fields
        if (!grossWeight || grossWeight <= 0) {
            return res.status(400).json({
                success: false,
                message: 'Gross weight must be greater than 0'
            });
        }

        // Validate dates
        if (expectedReturnDate && new Date(expectedReturnDate) < new Date(outDate)) {
            return res.status(400).json({
                success: false,
                message: 'Expected return date must be on or after out date'
            });
        }

        // Get user info
        const user = await User.findById(req.user.id);

        // Create outward movement record
        const movement = await OutwardMovement.create({
            itemId,
            movementType,
            outDate: outDate || moment().tz('Asia/Kolkata').toDate(),
            grossWeight,
            purity,
            expectedReturnDate,
            remarks,
            photos,
            givenTo,
            repairType,
            estimatedWeightLoss,
            jobCardNumber,
            customerName,
            customerMobile,
            idProofType,
            partyName,
            partyType,
            gstin,
            expectedSettlementDate,
            consignmentType,
            challanNumber,
            previousItemStatus: item.status,
            performedBy: req.user.id,
            performedByName: user ? user.name : 'Unknown',
            deviceId: req.headers['user-agent'] || 'unknown',
            ipAddress: req.ip || req.connection.remoteAddress
        });

        // Update item status based on movement type
        let newStatus;
        switch (movementType) {
            case 'REPAIR':
                newStatus = 'UNDER_REPAIR';
                break;
            case 'CUSTOMER_TRIAL':
                newStatus = 'WITH_CUSTOMER';
                break;
            case 'AGENT_CONSIGNMENT':
                newStatus = 'WITH_AGENT';
                break;
            default:
                newStatus = 'UNDER_REPAIR';
        }

        item.status = newStatus;
        await item.save();

        res.status(201).json({
            success: true,
            message: 'Item moved out successfully',
            data: { movement, item }
        });
    } catch (error) {
        console.error('Create outward movement error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while creating outward movement',
            error: error.message
        });
    }
};

// @desc    Return item from outward movement
// @route   PUT /api/outward-movements/:id/return
// @access  Private
exports.returnItem = async (req, res) => {
    try {
        const movement = await OutwardMovement.findById(req.params.id);

        if (!movement) {
            return res.status(404).json({
                success: false,
                message: 'Movement record not found'
            });
        }

        if (movement.status !== 'OUT') {
            return res.status(400).json({
                success: false,
                message: `Item already ${movement.status.toLowerCase()}`
            });
        }

        // Update movement status
        movement.status = 'RETURNED';
        movement.returnDate = moment().tz('Asia/Kolkata').toDate();
        await movement.save();

        // Restore item status
        const item = await Item.findById(movement.itemId);
        if (item) {
            // Restore to previous status or default to active
            item.status = movement.previousItemStatus === 'booked' ? 'booked' : 'active';
            await item.save();
        }

        res.status(200).json({
            success: true,
            message: 'Item returned successfully',
            data: { movement, item }
        });
    } catch (error) {
        console.error('Return item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while returning item',
            error: error.message
        });
    }
};

// @desc    Get all movements for an item
// @route   GET /api/outward-movements/item/:itemId
// @access  Private
exports.getItemMovements = async (req, res) => {
    try {
        const movements = await OutwardMovement.find({ itemId: req.params.itemId })
            .populate('performedBy', 'name email')
            .sort({ createdAt: -1 });

        res.status(200).json({
            success: true,
            count: movements.length,
            data: { movements }
        });
    } catch (error) {
        console.error('Get item movements error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching movements',
            error: error.message
        });
    }
};

// @desc    Get all outward movements
// @route   GET /api/outward-movements
// @access  Private
exports.getOutwardMovements = async (req, res) => {
    try {
        const { status, movementType } = req.query;

        const filter = {};
        if (status) filter.status = status;
        if (movementType) filter.movementType = movementType;

        const movements = await OutwardMovement.find(filter)
            .populate('itemId', 'name barcode netWeight metalType')
            .populate('performedBy', 'name email')
            .sort({ createdAt: -1 });

        res.status(200).json({
            success: true,
            count: movements.length,
            data: { movements }
        });
    } catch (error) {
        console.error('Get outward movements error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching movements',
            error: error.message
        });
    }
};

// @desc    Get single outward movement
// @route   GET /api/outward-movements/:id
// @access  Private
exports.getOutwardMovement = async (req, res) => {
    try {
        const movement = await OutwardMovement.findById(req.params.id)
            .populate('itemId')
            .populate('performedBy', 'name email');

        if (!movement) {
            return res.status(404).json({
                success: false,
                message: 'Movement record not found'
            });
        }

        res.status(200).json({
            success: true,
            data: { movement }
        });
    } catch (error) {
        console.error('Get outward movement error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching movement',
            error: error.message
        });
    }
};
