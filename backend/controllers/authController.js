const User = require('../models/User');
const { generateToken } = require('../middleware/auth');

// @desc    Login user
// @route   POST /api/auth/login
// @access  Public
exports.login = async (req, res) => {
    try {
        const { mobile, password } = req.body;

        // Validate input
        if (!mobile || !password) {
            return res.status(400).json({
                success: false,
                message: 'Please provide mobile number and password'
            });
        }

        // Check if user exists (include password for comparison)
        const user = await User.findOne({ mobile }).select('+password');

        if (!user) {
            return res.status(401).json({
                success: false,
                message: 'Invalid credentials'
            });
        }

        // Check if user is active
        if (!user.isActive) {
            return res.status(401).json({
                success: false,
                message: 'User account is inactive'
            });
        }

        // Check password
        const isPasswordMatch = await user.comparePassword(password);

        if (!isPasswordMatch) {
            return res.status(401).json({
                success: false,
                message: 'Invalid credentials'
            });
        }

        // Generate token
        const token = generateToken(user._id);

        res.status(200).json({
            success: true,
            message: 'Login successful',
            data: {
                token,
                user: {
                    id: user._id,
                    name: user.name,
                    mobile: user.mobile,
                    role: user.role,
                    language: user.language
                }
            }
        });
    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error during login'
        });
    }
};

// @desc    Register new user (admin only)
// @route   POST /api/auth/register
// @access  Private/Admin
exports.register = async (req, res) => {
    try {
        const { name, mobile, password, role, language } = req.body;

        // Validate input
        if (!name || !mobile || !password) {
            return res.status(400).json({
                success: false,
                message: 'Please provide name, mobile, and password'
            });
        }

        // Check if user already exists
        const existingUser = await User.findOne({ mobile });

        if (existingUser) {
            return res.status(400).json({
                success: false,
                message: 'User with this mobile number already exists'
            });
        }

        // Create user
        const user = await User.create({
            name,
            mobile,
            password,
            role: role || 'staff',
            language: language || 'en'
        });

        res.status(201).json({
            success: true,
            message: 'User registered successfully',
            data: {
                user: {
                    id: user._id,
                    name: user.name,
                    mobile: user.mobile,
                    role: user.role,
                    language: user.language
                }
            }
        });
    } catch (error) {
        console.error('Registration error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error during registration'
        });
    }
};

// @desc    Get current user
// @route   GET /api/auth/me
// @access  Private
exports.getMe = async (req, res) => {
    try {
        const user = await User.findById(req.user.id);

        res.status(200).json({
            success: true,
            data: { user }
        });
    } catch (error) {
        console.error('Get user error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error'
        });
    }
};

// @desc    Update user language preference
// @route   PUT /api/auth/language
// @access  Private
exports.updateLanguage = async (req, res) => {
    try {
        const { language } = req.body;

        if (!['en', 'bn'].includes(language)) {
            return res.status(400).json({
                success: false,
                message: 'Invalid language. Must be "en" or "bn"'
            });
        }

        const user = await User.findByIdAndUpdate(
            req.user.id,
            { language },
            { new: true, runValidators: true }
        );

        res.status(200).json({
            success: true,
            message: 'Language updated successfully',
            data: { user }
        });
    } catch (error) {
        console.error('Update language error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error'
        });
    }
};
