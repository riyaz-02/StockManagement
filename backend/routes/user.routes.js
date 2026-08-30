const express = require('express');
const router = express.Router();
const { protect, requirePermission } = require('../middleware/auth');
const {
    getUsers,
    getUser,
    createUser,
    updateUser,
    deleteUser,
    changePassword,
    registerFcmToken,
    resetPassword
} = require('../controllers/userController');
const { updateUserOverrides } = require('../controllers/permissionController');

// All routes require authentication
router.use(protect);

// Get all users (requires user management permission)
router.get('/', requirePermission('users.manage'), getUsers);

// Register/refresh this device's push token — must come before /:id so
// "fcm-token" isn't swallowed as an :id param.
router.put('/fcm-token', registerFcmToken);

// Get single user
router.get('/:id', getUser);

// Create user
router.post('/', requirePermission('users.manage'), createUser);

// Update user (self-or-admin/owner ownership check lives inside the
// controller, since a user must always be able to update their own profile)
router.put('/:id', updateUser);

// Change password (self-service, requires current password)
router.put('/:id/password', changePassword);

// Admin reset of another user's password (no current password needed)
router.put('/:id/reset-password', requirePermission('users.resetPassword'), resetPassword);

// Set/clear a user's individual permission overrides
router.put('/:id/permission-overrides', requirePermission('users.manage'), updateUserOverrides);

// Delete user
router.delete('/:id', requirePermission('users.manage'), deleteUser);

module.exports = router;
