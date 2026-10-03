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

        const beforeCfg = (await AppVersion.findOne({ isActive: true }).lean()) || {};
        const config = await AppVersion.findOneAndUpdate(
            { isActive: true },
            { $set: update },
            { new: true, upsert: true, setDefaultsOnInsert: true }
        );

        {
            const now = { version: config.latestVersion, code: config.latestVersionCode, forceUpdate: !!config.forceUpdate, downloadUrl: config.downloadUrl || '', message: config.updateMessage || '' };
            const was = { version: beforeCfg.latestVersion, code: beforeCfg.latestVersionCode, forceUpdate: !!beforeCfg.forceUpdate, downloadUrl: beforeCfg.downloadUrl || '', message: beforeCfg.updateMessage || '' };
            const changes = Object.keys(now).filter((k) => String(now[k]) !== String(was[k])).map((k) => ({ field: k, from: was[k], to: now[k] }));
            require('../services/audit').record(req, 'app_update', 'app', 'App version ' + config.latestVersion, 'published', changes);
        }
        require('../services/events').emit('app.update', { latestVersion: config.latestVersion, latestVersionCode: config.latestVersionCode, forceUpdate: !!config.forceUpdate, updateMessage: config.updateMessage || '' }, { actor: { id: req.user._id, name: req.user.name } });
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

// @desc    Turn the sign-in gate on/off (blocks new logins on the app and the website; admin/owner can always still sign in)
// @route   PUT /api/app-version/maintenance
// @access  Private/Admin
exports.updateMaintenanceMode = async (req, res) => {
    try {
        const enabled = req.body.enabled === true;
        const message = String(req.body.message || '').trim().slice(0, 200) || DEFAULTS.updateMessage;
        const before = (await AppVersion.findOne({ isActive: true }).lean()) || {};
        const config = await AppVersion.findOneAndUpdate(
            { isActive: true },
            { $set: { maintenanceMode: { enabled, message }, updatedBy: req.user.id } },
            { new: true, upsert: true, setDefaultsOnInsert: true }
        );
        const was = !!(before.maintenanceMode && before.maintenanceMode.enabled);
        if (was !== enabled) {
            require('../services/audit').record(req, 'app_update', 'app', 'Sign-in gate', enabled ? 'turned on' : 'turned off', [{ field: 'enabled', from: was, to: enabled }, { field: 'message', to: message }]);
        }
        res.status(200).json({ success: true, data: { appVersion: config } });
    } catch (error) {
        console.error('Update maintenance mode error:', error);
        res.status(500).json({ success: false, message: 'Server error while updating the sign-in gate' });
    }
};
