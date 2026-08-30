const User = require('../models/User');
const Notification = require('../models/Notification');
const { sendPushToTokens } = require('../config/firebaseAdmin');

// Resolves the target user set for a notification and flattens their
// registered device tokens into one list.
async function resolveTargetTokens({ targetType, targetRole }) {
    const filter = { isActive: true, 'fcmTokens.0': { $exists: true } };
    if (targetType === 'role') {
        filter.role = targetRole;
    }

    const users = await User.find(filter).select('fcmTokens');
    const tokens = [];
    users.forEach(u => u.fcmTokens.forEach(t => tokens.push(t.token)));
    return tokens;
}

// Removes tokens FCM reports as no-longer-valid (uninstalled app, etc.)
async function pruneInvalidTokens(invalidTokens) {
    if (!invalidTokens || invalidTokens.length === 0) return;
    await User.updateMany(
        { 'fcmTokens.token': { $in: invalidTokens } },
        { $pull: { fcmTokens: { token: { $in: invalidTokens } } } }
    );
}

// @desc    Send a push notification to all users or a specific role
// @route   POST /api/notifications/send
// @access  Private/Admin
exports.sendNotification = async (req, res) => {
    try {
        const { title, body, targetType, targetRole, data } = req.body;

        if (!title || !body) {
            return res.status(400).json({
                success: false,
                message: 'Please provide title and body',
            });
        }

        const resolvedTargetType = targetType === 'role' ? 'role' : 'all';
        if (resolvedTargetType === 'role' && !targetRole) {
            return res.status(400).json({
                success: false,
                message: 'Please provide targetRole when targetType is "role"',
            });
        }

        const tokens = await resolveTargetTokens({ targetType: resolvedTargetType, targetRole });

        const result = await sendPushToTokens(tokens, { title, body, data: data || {} });
        await pruneInvalidTokens(result.invalidTokens);

        const notification = await Notification.create({
            title,
            body,
            data: data || {},
            targetType: resolvedTargetType,
            targetRole: resolvedTargetType === 'role' ? targetRole : null,
            source: 'manual',
            sentBy: req.user.id,
            successCount: result.successCount,
            failureCount: result.failureCount,
        });

        res.status(200).json({
            success: true,
            message: result.disabled
                ? 'Notification saved, but push delivery is not configured yet (missing Firebase service account)'
                : `Sent to ${result.successCount} device(s)`,
            data: { notification, ...result },
        });
    } catch (error) {
        console.error('Send notification error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while sending notification',
        });
    }
};

// @desc    Get notification send history
// @route   GET /api/notifications
// @access  Private/Admin
exports.getNotificationHistory = async (req, res) => {
    try {
        const notifications = await Notification.find()
            .populate('sentBy', 'name')
            .sort({ createdAt: -1 })
            .limit(100);

        res.status(200).json({
            success: true,
            count: notifications.length,
            data: { notifications },
        });
    } catch (error) {
        console.error('Get notification history error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching notification history',
        });
    }
};

module.exports.resolveTargetTokens = resolveTargetTokens;
module.exports.pruneInvalidTokens = pruneInvalidTokens;
