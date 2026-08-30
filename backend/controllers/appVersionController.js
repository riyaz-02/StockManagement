const AppVersion = require('../models/AppVersion');

const DEFAULTS = {
    latestVersion: '1.0.0',
    latestVersionCode: 1,
    forceUpdate: false,
    downloadUrl: 'https://lgp.skriyaz.com/app',
    updateMessage: 'A new version of the app is available.',
};

// @desc    Get current app version config (public — checked before login)
// @route   GET /api/app-version
// @access  Public
exports.getAppVersion = async (req, res) => {
    try {
        const config = (await AppVersion.findOne({ isActive: true }).lean()) || DEFAULTS;

        res.status(200).json({
            success: true,
            data: { appVersion: config },
        });
    } catch (error) {
        console.error('Get app version error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching app version',
        });
    }
};

// @desc    Update app version config
// @route   PUT /api/app-version
// @access  Private/Admin
exports.updateAppVersion = async (req, res) => {
    try {
        const { latestVersion, latestVersionCode, forceUpdate, downloadUrl, updateMessage } = req.body;

        if (!latestVersion || latestVersionCode === undefined) {
            return res.status(400).json({
                success: false,
                message: 'Please provide latestVersion and latestVersionCode',
            });
        }

        const update = {
            latestVersion,
            latestVersionCode: Number(latestVersionCode),
            forceUpdate: !!forceUpdate,
            updatedBy: req.user.id,
        };
        if (downloadUrl !== undefined) update.downloadUrl = downloadUrl;
        if (updateMessage !== undefined) update.updateMessage = updateMessage;

        const config = await AppVersion.findOneAndUpdate(
            { isActive: true },
            { $set: update },
            { new: true, upsert: true, setDefaultsOnInsert: true }
        );

        res.status(200).json({
            success: true,
            message: 'App version updated',
            data: { appVersion: config },
        });
    } catch (error) {
        console.error('Update app version error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while updating app version',
        });
    }
};
