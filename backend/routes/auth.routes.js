const express = require('express');
const router = express.Router();
const { login, register, getMe, updateLanguage } = require('../controllers/authController');
const { protect, authorize } = require('../middleware/auth');

// Public routes
router.post('/login', login);

// Protected routes
router.get('/me', protect, getMe);
router.put('/language', protect, updateLanguage);

// Admin only routes
router.post('/register', protect, authorize('admin'), register);

module.exports = router;
