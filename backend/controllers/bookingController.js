const Booking = require('../models/Booking');
const Item = require('../models/Item');

// @desc    Create new booking
// @route   POST /api/bookings
// @access  Private
// @desc    Create new booking
// @route   POST /api/bookings
// @access  Private
exports.createBooking = async (req, res) => {
    try {
        const { itemId, customerName, mobile, address, expiryDate, advanceAmount, remarks } = req.body;
        const Customer = require('../models/Customer');

        // Validate required fields
        if (!itemId || !customerName || !mobile) {
            return res.status(400).json({
                success: false,
                message: 'Please provide item ID, customer name, and mobile number'
            });
        }

        const item = await Item.findById(itemId);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Check if item is available for booking
        if (item.status === 'booked') {
            return res.status(400).json({
                success: false,
                message: 'Item is already booked'
            });
        }

        if (!['active'].includes(item.status)) {
            return res.status(400).json({
                success: false,
                message: `Item is ${item.status} and cannot be booked`
            });
        }

        // Find or Create Customer
        let customer = await Customer.findOne({ mobile });
        if (!customer) {
            customer = await Customer.create({
                mobile,
                name: customerName,
                address
            });
        } else {
            // Update address if provided
            if (address) customer.address = address;
            await customer.save();
        }

        // Create booking
        const booking = await Booking.create({
            itemId,
            customerId: customer._id,
            customerName,
            mobile,
            expiryDate: expiryDate ? new Date(expiryDate) : null,
            advanceAmount: advanceAmount || 0,
            remarks: remarks || '',
            status: 'active'
        });

        // Link booking to customer
        customer.bookings.push(booking._id);
        await customer.save();

        // Update item status
        item.status = 'booked';
        await item.save();

        res.status(201).json({
            success: true,
            message: 'Booking created successfully',
            data: { booking }
        });
    } catch (error) {
        console.error('Create booking error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while creating booking'
        });
    }
};

// @desc    Get all bookings
// @route   GET /api/bookings
// @access  Private
exports.getBookings = async (req, res) => {
    try {
        const { status, mobile } = req.query;

        const filter = {};
        if (status) filter.status = status;
        if (mobile) filter.mobile = mobile;

        const bookings = await Booking.find(filter)
            .populate('itemId', 'name barcode itemType metalType netWeight images')
            .sort({ bookingDate: -1 });

        res.status(200).json({
            success: true,
            count: bookings.length,
            data: { bookings }
        });
    } catch (error) {
        console.error('Get bookings error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching bookings'
        });
    }
};

// @desc    Get single booking
// @route   GET /api/bookings/:id
// @access  Private
exports.getBooking = async (req, res) => {
    try {
        const booking = await Booking.findById(req.params.id)
            .populate('itemId', 'name barcode itemType metalType netWeight images');

        if (!booking) {
            return res.status(404).json({
                success: false,
                message: 'Booking not found'
            });
        }

        res.status(200).json({
            success: true,
            data: { booking }
        });
    } catch (error) {
        console.error('Get booking error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching booking'
        });
    }
};



// @desc    Update booking details
// @route   PUT /api/bookings/:id
// @access  Private
exports.updateBooking = async (req, res) => {
    try {
        const { customerName, mobile, address, expiryDate, advanceAmount, remarks, status } = req.body;
        const Booking = require('../models/Booking');
        const Item = require('../models/Item');
        const Customer = require('../models/Customer');

        let booking = await Booking.findById(req.params.id);

        if (!booking) {
            return res.status(404).json({
                success: false,
                message: 'Booking not found'
            });
        }

        // Update fields if provided
        if (customerName) booking.customerName = customerName;
        if (mobile) booking.mobile = mobile;
        if (expiryDate) booking.expiryDate = new Date(expiryDate);
        if (advanceAmount !== undefined) booking.advanceAmount = advanceAmount;
        if (remarks) booking.remarks = remarks;

        // Handle Status Change
        if (status) {
            // Logic for specific statuses
            if (status === 'manufacturing') {
                // If moving to manufacturing, release the item
                if (booking.status !== 'manufacturing') {
                    const item = await Item.findById(booking.itemId);
                    if (item && item.status === 'booked') {
                        item.status = 'active';
                        await item.save();
                    }
                }
            } else if (status === 'cancelled') {
                // Reuse cancel logic? Or just handle here.
                const item = await Item.findById(booking.itemId);
                if (item && item.status === 'booked') {
                    item.status = 'active';
                    await item.save();
                }
            }
            booking.status = status;
        }

        await booking.save();

        // Update Customer Address/Name if changed
        if (booking.customerId) {
            const customer = await Customer.findById(booking.customerId);
            if (customer) {
                if (customerName) customer.name = customerName;
                if (address) customer.address = address;
                await customer.save();
            }
        }

        res.status(200).json({
            success: true,
            data: { booking }
        });
    } catch (error) {
        console.error('Update booking error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while updating booking'
        });
    }
};

// @desc    Cancel booking
// @route   PUT /api/bookings/:id/cancel
// @access  Private
exports.cancelBooking = async (req, res) => {
    try {
        const booking = await Booking.findById(req.params.id);

        if (!booking) {
            return res.status(404).json({
                success: false,
                message: 'Booking not found'
            });
        }

        if (booking.status === 'cancelled') {
            return res.status(400).json({
                success: false,
                message: 'Booking is already cancelled'
            });
        }

        // Update booking status
        booking.status = 'cancelled';
        await booking.save();

        // Update item status back to active
        const item = await Item.findById(booking.itemId);
        if (item && item.status === 'booked') {
            item.status = 'active';
            await item.save();
        }

        res.status(200).json({
            success: true,
            message: 'Booking cancelled successfully',
            data: { booking }
        });
    } catch (error) {
        console.error('Cancel booking error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while cancelling booking'
        });
    }
};

// @desc    Complete booking (item sold)
// @route   PUT /api/bookings/:id/complete
// @access  Private
exports.completeBooking = async (req, res) => {
    try {
        const booking = await Booking.findById(req.params.id);

        if (!booking) {
            return res.status(404).json({
                success: false,
                message: 'Booking not found'
            });
        }

        if (booking.status === 'completed') {
            return res.status(400).json({
                success: false,
                message: 'Booking is already completed'
            });
        }

        // Update booking status
        booking.status = 'completed';
        await booking.save();

        // Update item status to sold
        const item = await Item.findById(booking.itemId);
        if (item) {
            item.status = 'sold';

            // Free up container slot
            if (item.containerId && item.slotNumber) {
                const Container = require('../models/Container');
                const container = await Container.findById(item.containerId);
                if (container) {
                    const slot = container.slots.find(s => s.slotNumber === item.slotNumber);
                    if (slot) {
                        slot.itemId = null;
                        slot.reserved = false;
                        await container.save();
                    }
                }
            }

            item.containerId = null;
            item.slotNumber = null;
            await item.save();
        }

        res.status(200).json({
            success: true,
            message: 'Booking completed successfully',
            data: { booking }
        });
    } catch (error) {
        console.error('Complete booking error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while completing booking'
        });
    }
};
