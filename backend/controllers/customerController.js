const Booking = require('../models/Booking');
const store = require('../services/customerStore');

const by = (req) => ({ id: String(req.user._id), name: req.user.name || '', branchId: req.user.branchId, branchName: req.user.branchName });

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

        // The website's customer with this number (any of their numbers), made the website's way if new.
        // An existing customer's name and address are NOT changed from here.
        const { customer } = await store.findOrCreate({ name, mobile, address }, by(req));
        await store.addToWishlist(customer, itemId, by(req));

        res.status(200).json({
            success: true,
            data: { customer: { _id: customer._id, ...store.display(customer) } }
        });
    } catch (error) {
        console.error('Wishlist error:', error);
        res.status(error.statusCode || 500).json({
            success: false,
            message: error.statusCode ? error.message : 'Server error'
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

        const customer = await store.findByNumber(mobile);
        if (customer) await store.removeFromWishlist(customer, itemId);

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

        // Customers who have this item in their wishlist (active)
        const wishlistedBy = (await store.wishlistedBy(itemId)).map(({ customer, addedAt }) => ({
            ...store.display(customer),
            date: addedAt
        }));

        // Bookings for this item (exclude cancelled)
        const bookings = await Booking.find({
            itemId,
            status: { $ne: 'cancelled' }
        });
        const people = new Map((await store.byIds(bookings.map((b) => b.customerId).filter(Boolean))).map((c) => [String(c._id), c]));

        const bookedBy = bookings.map(b => ({
            id: b._id,
            name: b.customerName, // the booking's own snapshot
            mobile: b.mobile,
            address: b.customerId ? (people.get(String(b.customerId)) || {}).address : undefined,
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
