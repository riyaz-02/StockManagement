const Settings = require('../models/Settings');

// Get tag settings
exports.getTagSettings = async (req, res) => {
    try {
        console.log('📋 [Tag Settings] GET /api/tag-settings called');

        // Fetch purity options from existing settings
        const puritySettings = await Settings.findOne({ category: 'item', type: 'purityOptions' });
        console.log('📋 [Tag Settings] Purity settings from DB:', puritySettings);

        const purityOptions = puritySettings?.values || [];
        console.log('📋 [Tag Settings] Extracted purity options:', purityOptions);

        // Fetch tag settings
        let tagSettings = await Settings.findOne({ category: 'tag', type: 'printing' });
        console.log('📋 [Tag Settings] Existing tag settings from DB:', tagSettings);

        // If no settings exist, create default with purity colors
        if (!tagSettings) {
            // Default colors for common purities
            const defaultColors = {
                '916': '#FFD700',      // Gold
                '22k': '#FFD700',      // Gold
                '18k': '#FFC0CB',      // Rose Gold
                '24k': '#FFDF00',      // Bright Gold
                'silver': '#C0C0C0',   // Silver
                '14k': '#DAA520',      // Goldenrod
                '20k': '#FFD700',      // Gold
            };

            // Create color mappings for all purity options
            const purityColors = purityOptions.map(purity => ({
                purity: purity,
                color: defaultColors[purity.toLowerCase()] || '#FFD700' // Default to gold
            }));

            tagSettings = await Settings.create({
                category: 'tag',
                type: 'printing',
                values: [],
                tagSettings: {
                    tagWidth: 50,
                    tagHeight: 30,
                    purityColors: purityColors
                }
            });
        } else {
            // Update purity colors if new purities were added
            const existingPurities = tagSettings.tagSettings?.purityColors?.map(pc => pc.purity) || [];
            const newPurities = purityOptions.filter(p => !existingPurities.includes(p));

            if (newPurities.length > 0) {
                const newColors = newPurities.map(purity => ({
                    purity: purity,
                    color: '#FFD700' // Default gold color for new purities
                }));

                tagSettings.tagSettings.purityColors = [
                    ...(tagSettings.tagSettings.purityColors || []),
                    ...newColors
                ];
                await tagSettings.save();
            }
        }

        const response = {
            tagWidth: tagSettings.tagSettings?.tagWidth || 50,
            tagHeight: tagSettings.tagSettings?.tagHeight || 30,
            purityColors: tagSettings.tagSettings?.purityColors || [],
            availablePurities: purityOptions
        };

        console.log('📋 [Tag Settings] Sending response:', JSON.stringify(response, null, 2));
        res.json(response);
    } catch (error) {
        console.error('Error fetching tag settings:', error);
        res.status(500).json({ message: 'Error fetching tag settings', error: error.message });
    }
};

// Update tag settings
exports.updateTagSettings = async (req, res) => {
    try {
        const { tagWidth, tagHeight, purityColors } = req.body;

        let settings = await Settings.findOne({ category: 'tag', type: 'printing' });

        if (!settings) {
            settings = new Settings({
                category: 'tag',
                type: 'printing',
                values: [],
                tagSettings: {}
            });
        }

        // Update tag settings
        settings.tagSettings = {
            tagWidth: tagWidth || 50,
            tagHeight: tagHeight || 30,
            purityColors: purityColors || []
        };

        settings.updatedBy = req.user?._id;
        await settings.save();

        res.json({ message: 'Tag settings updated successfully', tagSettings: settings.tagSettings });
    } catch (error) {
        console.error('Error updating tag settings:', error);
        res.status(500).json({ message: 'Error updating tag settings', error: error.message });
    }
};
