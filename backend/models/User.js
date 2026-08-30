const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
    name: {
        type: String,
        required: [true, 'Name is required'],
        trim: true
    },
    role: {
        type: String,
        enum: ['admin', 'owner', 'manager', 'staff', 'viewer'],
        default: 'staff',
        required: true
    },
    // Explicit per-user permission overrides (only ever populated for
    // manager/staff/viewer accounts — admin/owner always bypass every
    // check and never have overrides). Sparse: only keys that differ from
    // the role's default grid (see config/permissions.js) need to be set.
    // Plain Mixed object, not a Mongoose Map — Map keys can't contain "."
    // and every permission key here is dot-namespaced (e.g. "items.delete").
    permissionOverrides: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    language: {
        type: String,
        enum: ['en', 'bn'],
        default: 'en'
    },
    mobile: {
        type: String,
        required: [true, 'Mobile number is required'],
        unique: true,
        trim: true
    },
    password: {
        type: String,
        required: [true, 'Password is required'],
        minlength: 6,
        select: false
    },
    profileImage: {
        type: String,
        default: null
    },
    isActive: {
        type: Boolean,
        default: true
    },
    // Push notification device tokens (one account can have multiple devices)
    fcmTokens: [{
        token: { type: String, required: true },
        platform: { type: String, default: 'android' },
        updatedAt: { type: Date, default: Date.now }
    }],
    createdAt: {
        type: Date,
        default: Date.now
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
});

// ======================
// INDEXES FOR PERFORMANCE
// ======================

// Note: mobile field already has a unique index from schema definition (line 24)

// Index on role for authorization queries
userSchema.index({ role: 1 });

// Compound index for active users by role
userSchema.index({ isActive: 1, role: 1 });

// ======================
// METHODS
// ======================

// Hash password before saving
userSchema.pre('save', async function (next) {
    if (!this.isModified('password')) {
        return next();
    }

    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
    this.updatedAt = Date.now();
    next();
});

// Method to compare password
userSchema.methods.comparePassword = async function (candidatePassword) {
    return await bcrypt.compare(candidatePassword, this.password);
};

// Remove password from JSON output
userSchema.methods.toJSON = function () {
    const obj = this.toObject();
    delete obj.password;
    return obj;
};

module.exports = mongoose.model('User', userSchema);
