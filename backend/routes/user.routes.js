const express = require('express');
const router = express.Router();
const { protect, authorize } = require('../middleware/auth');
const {
    getUsers,
    getUser,
    createUser,
    updateUser,
    deleteUser,
    changePassword,
    registerFcmToken
} = require('../controllers/userController');

// All routes require authentication
router.use(protect);

// Get all users (admin only)
router.get('/', authorize('admin'), getUsers);

// Register/refresh this device's push token — must come before /:id so
// "fcm-token" isn't swallowed as an :id param.
router.put('/fcm-token', registerFcmToken);

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
