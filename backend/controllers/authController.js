const User = require('../models/User');
const { generateToken, REMEMBER_EXPIRE } = require('../middleware/auth');

// @desc    Login user
// @route   POST /api/auth/login
// @access  Public
exports.login = async (req, res) => {
    try {
        const { mobile, password } = req.body;
        // the app sends remember:true so a phone stays signed in (its PIN / fingerprint guard the screen); the website does not
        const remember = req.body.remember === true || req.body.remember === 'true';

        // Validate input
        if (!mobile || !password) {
            return res.status(400).json({
                success: false,
                message: 'Please provide mobile number and password'
            });
        }

        // The app signs in with a mobile number; the website's people also have a username / e-mail: all three work
        const user = await User.findByLogin(mobile, true);

        if (!user) {
            return res.status(401).json({
                success: false,
                message: 'Invalid credentials'
            });
        }

        // A temporary sign-in gate (Admin Control > App updates); admin/owner can always still get in to turn it off.
        if (!['admin', 'owner'].includes(user.role)) {
            const AppVersion = require('../models/AppVersion');
            const cfg = await AppVersion.findOne({ isActive: true }).select('maintenanceMode').lean();
            if (cfg && cfg.maintenanceMode && cfg.maintenanceMode.enabled) {
                return res.status(503).json({ success: false, message: cfg.maintenanceMode.message || 'The app is temporarily unavailable. Please try again shortly.', maintenance: true });
            }
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

        // The website shows "last login" for everyone: a sign-in from the app counts too
        User.updateOne({ _id: user._id }, { $set: { last_login: new Date(), last_login_ist: User.istText() } }).catch(() => {});

        // Generate token
        const token = remember ? generateToken(user._id, REMEMBER_EXPIRE()) : generateToken(user._id);

        res.status(200).json({
            success: true,
            message: 'Login successful',
            data: {
                token,
                user: {
                    id: user._id,
                    name: user.name,
                    mobile: user.mobile || '',
                    username: user.username || '',
                    role: user.role,
                    language: user.language,
                    branchId: user.branchId || 'main',
                    branchName: user.branchName || 'Main branch'
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

// @desc    Swap a still-valid token for a fresh long one (the app calls this each time it opens: a phone in daily use never
//          has to sign in again; one unused for longer than the token lives does)
// @route   POST /api/auth/refresh
// @access  Private
exports.refresh = async (req, res) => {
    try {
        res.json({ success: true, data: { token: generateToken(req.user._id, REMEMBER_EXPIRE()) } });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server error' });
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

        // Check if user already exists (the website's people count too: mobile, username or e-mail)
        const clash = await User.taken({ mobile, username: mobile });
        if (clash) {
            return res.status(400).json({
                success: false,
                message: `User with this ${clash} already exists`
            });
        }

        // Create user (in the website's own format, so the website treats them as one of its own)
        const user = await User.create(User.forCreate({ name, mobile, password, role: role || 'staff', language: language || 'en' }));

        res.status(201).json({
            success: true,
            message: 'User registered successfully',
            data: {
                user: {
                    id: user._id,
                    name: user.name,
                    mobile: user.mobile,
                    role: user.role,
                    language: user.language,
                    branchId: user.branchId || 'main',
                    branchName: user.branchName || 'Main branch'
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
