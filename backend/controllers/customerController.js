const Customer = require('../models/Customer');
const Booking = require('../models/Booking');

// @desc    Add item to wishlist
// @route   POST /api/customers/wishlist
// @access  Private
exports.addToWishlist = async (req, res) => {
    try {
        const { mobile, name, address, itemId } = req.body;

        if (!mobile || !itemId) {
            return res.status(400).json({
                success: false,
                message: 'Mobile and Item ID are required'
            });
        }

        // Find or create customer
        let customer = await Customer.findOne({ mobile });
        if (!customer) {
            customer = await Customer.create({
                mobile,
                name,
                address,
                wishlist: [{ item: itemId }]
            });
        } else {
            // Update details if provided
            if (name) customer.name = name;
            if (address) customer.address = address;

            // Check if item already in wishlist
            const existingWishlistItem = customer.wishlist.find(w => w.item.toString() === itemId);
            if (!existingWishlistItem) {
                customer.wishlist.push({ item: itemId, status: 'active' });
            } else if (existingWishlistItem.status === 'removed') {
                existingWishlistItem.status = 'active';
                existingWishlistItem.addedAt = Date.now();
            }
            await customer.save();
        }

        res.status(200).json({
            success: true,
            data: { customer }
        });
    } catch (error) {
        console.error('Wishlist error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error'
        });
    }
};

// @desc    Remove item from wishlist
// @route   POST /api/customers/wishlist/remove
// @access  Private
exports.removeFromWishlist = async (req, res) => {
    try {
        const { mobile, itemId } = req.body;

        if (!mobile || !itemId) {
            return res.status(400).json({
                success: false,
                message: 'Mobile and Item ID are required'
            });
        }

        const customer = await Customer.findOne({ mobile });

        if (customer) {
            const wItem = customer.wishlist.find(w => w.item.toString() === itemId);
            if (wItem) {
                wItem.status = 'removed';
                await customer.save();
            }
        }

        res.status(200).json({
            success: true,
            message: 'Removed from wishlist'
        });
    } catch (error) {
        console.error('Remove from wishlist error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error'
        });
    }
};

// @desc    Get customers interested in an item (Wishlist or Booking)
// @route   GET /api/customers/item/:itemId
// @access  Private
exports.getItemInteractions = async (req, res) => {
    try {
        const { itemId } = req.params;

        // Find customers who have this item in wishlist (active)
        const wishlistCustomers = await Customer.find({
            wishlist: { $elemMatch: { item: itemId, status: 'active' } }
        }).select('name mobile address wishlist bookings');

        // Find bookings for this item (exclude cancelled)
        const bookings = await Booking.find({
            itemId,
            status: { $ne: 'cancelled' }
        }).populate('customerId');

        // Merge lists? 
        // Actually, let's just return the two lists separately for the UI to display.

        // Wishlisted By
        const wishlistedBy = wishlistCustomers.map(c => ({
            name: c.name,
            mobile: c.mobile,
            address: c.address,
            date: c.wishlist.find(w => w.item.toString() === itemId && w.status === 'active')?.addedAt
        }));

        // Booked By
        const bookedBy = bookings.map(b => ({
            id: b._id,
            name: b.customerName, // Use booking snapshot or b.customerId.name
            mobile: b.mobile,
            address: b.customerId?.address,
            bookingDate: b.bookingDate,
            expiryDate: b.expiryDate,
            advance: b.advanceAmount,
            status: b.status,
            remarks: b.remarks
        }));

        res.status(200).json({
            success: true,
            data: {
                wishlistedBy,
                bookedBy
            }
        });

    } catch (error) {
        console.error('Get interactions error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error'
        });
    }
};
