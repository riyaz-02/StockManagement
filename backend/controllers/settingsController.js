const Settings = require('../models/Settings');

// @desc    Get all settings for a category
// @route   GET /api/settings/:category
// @access  Private
exports.getSettingsByCategory = async (req, res) => {
    try {
        const { category } = req.params;

        const settings = await Settings.find({ category });

        // Convert to object format { type: values }
        const settingsObj = {};
        settings.forEach(setting => {
            settingsObj[setting.type] = setting.values;
        });

        res.json({
            success: true,
            data: settingsObj,
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message,
        });
    }
};

// @desc    Get specific setting
// @route   GET /api/settings/:category/:type
// @access  Private
exports.getSettingByType = async (req, res) => {
    try {
        const { category, type } = req.params;

        const setting = await Settings.findOne({ category, type });

        if (!setting) {
            return res.status(404).json({
                success: false,
                message: 'Setting not found',
            });
        }

        res.json({
            success: true,
            data: setting.values,
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message,
        });
    }
};

// @desc    Update setting values
// @route   PUT /api/settings/:category/:type
// @access  Private/Admin
exports.updateSetting = async (req, res) => {
    try {
        const { category, type } = req.params;
        const { values } = req.body;

        if (!Array.isArray(values)) {
            return res.status(400).json({
                success: false,
                message: 'Values must be an array',
            });
        }

        const setting = await Settings.findOneAndUpdate(
            { category, type },
            {
                values,
                updatedBy: req.user._id,
            },
            { new: true, upsert: true }
        );

        res.json({
            success: true,
            data: setting,
            message: 'Setting updated successfully',
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message,
        });
    }
};

// @desc    Add value to setting
// @route   POST /api/settings/:category/:type/add
// @access  Private/Admin
exports.addValue = async (req, res) => {
    try {
        const { category, type } = req.params;
        const { value } = req.body;

        if (!value) {
            return res.status(400).json({
                success: false,
                message: 'Value is required',
            });
        }

        const setting = await Settings.findOne({ category, type });

        if (!setting) {
            // Create new setting if doesn't exist
            const newSetting = await Settings.create({
                category,
                type,
                values: [value],
                updatedBy: req.user._id,
            });

            return res.json({
                success: true,
                data: newSetting,
                message: 'Value added successfully',
            });
        }

        // Check if value already exists
        if (setting.values.includes(value)) {
            return res.status(400).json({
                success: false,
                message: 'Value already exists',
            });
        }

        setting.values.push(value);
        setting.updatedBy = req.user._id;
        await setting.save();

        res.json({
            success: true,
            data: setting,
            message: 'Value added successfully',
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message,
        });
    }
};

// @desc    Delete value from setting
// @route   DELETE /api/settings/:category/:type/:value
// @access  Private/Admin
exports.deleteValue = async (req, res) => {
    try {
        const { category, type, value } = req.params;

        const setting = await Settings.findOne({ category, type });

        if (!setting) {
            return res.status(404).json({
                success: false,
                message: 'Setting not found',
            });
        }

        const index = setting.values.indexOf(value);
        if (index === -1) {
            return res.status(404).json({
                success: false,
                message: 'Value not found',
            });
        }

        setting.values.splice(index, 1);
        setting.updatedBy = req.user._id;
        await setting.save();

        res.json({
            success: true,
            data: setting,
            message: 'Value deleted successfully',
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message,
        });
    }
};

// @desc    Initialize default settings
// @route   POST /api/settings/initialize
// @access  Private/Admin
exports.initializeSettings = async (req, res) => {
    try {
        const defaultSettings = [
            {
                category: 'item',
                type: 'itemTypes',
                values: ['ring', 'necklace', 'earring', 'bracelet', 'pendant', 'chain', 'bangle'],
            },
            {
                category: 'item',
                type: 'metalTypes',
                values: ['gold', 'silver', 'mixed', 'gold-coated', 'platinum'],
            },
            {
                category: 'item',
                type: 'purityOptions',
                values: ['916', '22k', '18k', '14k', 'silver925', 'silver999', 'platinum950'],
            },
            {
                category: 'container',
                type: 'containerTypes',
                values: ['drawer', 'shelf', 'box', 'tray', 'custom'],
            },
            {
                category: 'container',
                type: 'weightCategories',
                values: ['light', 'medium', 'heavy', 'mixed'],
            },
            {
                category: 'container',
                type: 'layoutTypes',
                values: ['grid', 'linear', 'custom'],
            },
        ];

        for (const setting of defaultSettings) {
            await Settings.findOneAndUpdate(
                { category: setting.category, type: setting.type },
                { ...setting, updatedBy: req.user._id },
                { upsert: true }
            );
        }

        res.json({
            success: true,
            message: 'Settings initialized successfully',
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: error.message,
        });
    }
};
