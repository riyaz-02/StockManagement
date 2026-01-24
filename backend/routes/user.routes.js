const express = require('express');
const router = express.Router();
const { protect, authorize } = require('../middleware/auth');
const {
    getUsers,
    getUser,
    createUser,
    updateUser,
    deleteUser,
    changePassword
} = require('../controllers/userController');

// All routes require authentication
router.use(protect);

// Get all users (admin only)
router.get('/', authorize('admin'), getUsers);

// Get single user
router.get('/:id', getUser);

// Create user (admin only)
router.post('/', authorize('admin'), createUser);

// Update user
router.put('/:id', updateUser);

// Change password
router.put('/:id/password', changePassword);

// Delete user (admin only)
router.delete('/:id', authorize('admin'), deleteUser);

module.exports = router;
