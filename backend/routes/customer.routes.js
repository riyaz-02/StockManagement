const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/auth');
const { addToWishlist, removeFromWishlist, getItemInteractions } = require('../controllers/customerController');

router.post('/wishlist', protect, addToWishlist);
router.post('/wishlist/remove', protect, removeFromWishlist);
router.get('/item/:itemId', protect, getItemInteractions);

module.exports = router;
