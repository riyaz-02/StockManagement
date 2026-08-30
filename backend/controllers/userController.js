const User = require('../models/User');
const cloudinaryHelper = require('../utils/cloudinaryHelper');
const { hasPermission } = require('../middleware/auth');

// @desc    Get all users
// @route   GET /api/users
// @access  Private/Admin
exports.getUsers = async (req, res) => {
    try {
        const users = await User.find({ isActive: true })
            .select('-password')
            .sort({ createdAt: -1 });

        res.status(200).json({
            success: true,
            count: users.length,
            data: { users }
        });
    } catch (error) {
        console.error('Get users error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching users'
        });
    }
};

// @desc    Get single user
// @route   GET /api/users/:id
// @access  Private
exports.getUser = async (req, res) => {
    try {
        const user = await User.findById(req.params.id).select('-password');

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found'
            });
        }

        res.status(200).json({
            success: true,
            data: { user }
        });
    } catch (error) {
        console.error('Get user error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching user'
        });
    }
};

// @desc    Create new user
// @route   POST /api/users
// @access  Private/Admin
exports.createUser = async (req, res) => {
    try {
        const { name, mobile, password, role, profileImage } = req.body;

        // Validate required fields
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
            profileImage
        });

        // Remove password from response
        const userResponse = user.toJSON();

        res.status(201).json({
            success: true,
            message: 'User created successfully',
            data: { user: userResponse }
        });
    } catch (error) {
        console.error('Create user error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while creating user'
        });
    }
};

// @desc    Update user
// @route   PUT /api/users/:id
// @access  Private
exports.updateUser = async (req, res) => {
    try {
        const { name, mobile, profileImage, language, role, isActive } = req.body;

        const user = await User.findById(req.params.id);

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found'
            });
        }

        // Must be updating your own profile, or have user-management permission
        if (req.user.id !== req.params.id && !(await hasPermission(req.user, 'users.manage'))) {
            return res.status(403).json({
                success: false,
                message: 'Not authorized to update this user'
            });
        }

        // Update fields
        if (name) user.name = name;
        if (mobile) {
            // Check if mobile is already taken by another user
            const existingUser = await User.findOne({ mobile, _id: { $ne: req.params.id } });
            if (existingUser) {
                return res.status(400).json({
                    success: false,
                    message: 'Mobile number already in use'
                });
            }
            user.mobile = mobile;
        }
        if (profileImage !== undefined) {
            // Delete old profile image from Cloudinary if exists
            if (user.profileImage && user.profileImage !== profileImage) {
                try {
                    await cloudinaryHelper.deleteCloudinaryImages([user.profileImage]);
                } catch (err) {
                    console.error('Failed to delete old profile image:', err);
                }
            }
            user.profileImage = profileImage;
        }
        if (language) user.language = language;

        // Role and active-status changes require user-management permission,
        // and nobody can demote/deactivate their own account this way (avoids
        // locking everyone out if there's only one admin).
        if (
            req.user.id !== req.params.id &&
            (await hasPermission(req.user, 'users.manage'))
        ) {
            if (role) user.role = role;
            if (isActive !== undefined) user.isActive = isActive;
        }

        user.updatedAt = Date.now();

        await user.save();

        const userResponse = user.toJSON();

        res.status(200).json({
            success: true,
            message: 'User updated successfully',
            data: { user: userResponse }
        });
    } catch (error) {
        console.error('Update user error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while updating user'
        });
    }
};

// @desc    Delete user
// @route   DELETE /api/users/:id
// @access  Private/Admin
exports.deleteUser = async (req, res) => {
    try {
        const user = await User.findById(req.params.id);

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found'
            });
        }

        // Prevent deleting yourself
        if (req.user.id === req.params.id) {
            return res.status(400).json({
                success: false,
                message: 'Cannot delete your own account'
            });
        }

        // Soft delete
        user.isActive = false;
        user.updatedAt = Date.now();
        await user.save();

        res.status(200).json({
            success: true,
            message: 'User deleted successfully'
        });
    } catch (error) {
        console.error('Delete user error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while deleting user'
        });
    }
};

// @desc    Change password
// @route   PUT /api/users/:id/password
// @access  Private
exports.changePassword = async (req, res) => {
    try {
        const { currentPassword, newPassword } = req.body;

        // Validate required fields
        if (!currentPassword || !newPassword) {
            return res.status(400).json({
                success: false,
                message: 'Please provide current and new password'
            });
        }

        // Validate new password length
        if (newPassword.length < 6) {
            return res.status(400).json({
                success: false,
                message: 'New password must be at least 6 characters'
            });
        }

        // Get user with password field
        const user = await User.findById(req.params.id).select('+password');

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found'
            });
        }

        // Check if user is changing their own password
        if (req.user.id !== req.params.id) {
            return res.status(403).json({
                success: false,
                message: 'Not authorized to change this password'
            });
        }

        // Verify current password
        const isMatch = await user.comparePassword(currentPassword);
        if (!isMatch) {
            return res.status(401).json({
                success: false,
                message: 'Current password is incorrect'
            });
        }

        // Update password
        user.password = newPassword;
        user.updatedAt = Date.now();
        await user.save();

        res.status(200).json({
            success: true,
            message: 'Password changed successfully'
        });
    } catch (error) {
        console.error('Change password error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while changing password'
        });
    }
};

// @desc    Register/refresh the calling device's FCM push token
// @route   PUT /api/users/fcm-token
// @access  Private
exports.registerFcmToken = async (req, res) => {
    try {
        const { token, platform } = req.body;

        if (!token) {
            return res.status(400).json({
                success: false,
                message: 'Please provide a token'
            });
        }

        const user = await User.findById(req.user.id);

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found'
            });
        }

        const existing = user.fcmTokens.find(t => t.token === token);
        if (existing) {
            existing.platform = platform || existing.platform;
            existing.updatedAt = new Date();
        } else {
            user.fcmTokens.push({ token, platform: platform || 'android', updatedAt: new Date() });
        }

        await user.save();

        res.status(200).json({
            success: true,
            message: 'Device registered for notifications'
        });
    } catch (error) {
        console.error('Register FCM token error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while registering device'
        });
    }
};

// @desc    Admin reset of another user's password (no current password needed)
// @route   PUT /api/users/:id/reset-password
// @access  Private/Admin
exports.resetPassword = async (req, res) => {
    try {
        const { newPassword } = req.body;

        if (!newPassword) {
            return res.status(400).json({
                success: false,
                message: 'Please provide newPassword'
            });
        }

        if (newPassword.length < 6) {
            return res.status(400).json({
                success: false,
                message: 'New password must be at least 6 characters'
            });
        }

        const user = await User.findById(req.params.id);

        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found'
            });
        }

        user.password = newPassword;
        user.updatedAt = Date.now();
        await user.save();

        res.status(200).json({
            success: true,
            message: 'Password reset successfully'
        });
    } catch (error) {
        console.error('Reset password error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while resetting password'
        });
    }
};
