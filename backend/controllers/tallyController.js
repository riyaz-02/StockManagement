const TallySession = require('../models/TallySession');
const Item = require('../models/Item');

// @desc    Start new tally session
// @route   POST /api/tally/start
// @access  Private
exports.startTally = async (req, res) => {
    try {
        const { description } = req.body;

        // Calculate expected total weight (only active and booked items)
        const items = await Item.find({
            status: { $in: ['active', 'booked'] }
        });

        let expectedTotalWeight = 0;
        const weightByMetal = {
            gold: 0,
            silver: 0,
            platinum: 0,
            mixed: 0
        };

        items.forEach(item => {
            expectedTotalWeight += item.netWeight;
            if (weightByMetal.hasOwnProperty(item.metalType)) {
                weightByMetal[item.metalType] += item.netWeight;
            } else {
                weightByMetal.mixed += item.netWeight;
            }
        });

        // Get excluded items (repair, in_repair, temporarily_removed, sold)
        const excludedItems = await Item.find({
            status: { $in: ['repair', 'in_repair', 'temporarily_removed', 'sold'] }
        }).select('barcode name itemType metalType netWeight status');
        const excludedItemsData = excludedItems.map(item => ({
            itemId: item._id,
            reason: item.status
        }));

        // Create tally session
        const tallySession = await TallySession.create({
            date: new Date(),
            description: description || '',
            scannedItemIds: [],
            totalScannedWeight: 0,
            expectedTotalWeight,
            weightByMetal,
            excludedItems: excludedItemsData,
            mismatchDetected: false,
            status: 'in_progress',
            createdBy: req.user.id
        });

        res.status(201).json({
            success: true,
            message: 'Tally session started',
            data: {
                tallySession,
                expectedItemCount: items.length,
                excludedItemCount: excludedItems.length
            }
        });
    } catch (error) {
        console.error('Start tally error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while starting tally'
        });
    }
};

// @desc    Scan item during tally
// @route   POST /api/tally/scan
// @access  Private
exports.scanItemInTally = async (req, res) => {
    try {
        const { tallySessionId, barcode } = req.body;

        if (!tallySessionId || !barcode) {
            return res.status(400).json({
                success: false,
                message: 'Please provide tally session ID and barcode'
            });
        }

        const tallySession = await TallySession.findById(tallySessionId);

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        if (tallySession.status === 'locked') {
            return res.status(400).json({
                success: false,
                message: 'Tally session is locked. Cannot scan more items.'
            });
        }

        // Find item
        const item = await Item.findOne({ barcode });

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Check if item should be in tally
        if (!item.isInTally()) {
            return res.status(400).json({
                success: false,
                message: `Item is ${item.status} and should not be counted in tally`
            });
        }

        // Check for double scan
        const alreadyScanned = tallySession.scannedItemIds.some(
            id => id.toString() === item._id.toString()
        );

        if (alreadyScanned) {
            return res.status(400).json({
                success: false,
                message: 'Item already scanned in this tally session',
                data: { item }
            });
        }

        // Add item to scanned list
        tallySession.scannedItemIds.push(item._id);
        tallySession.totalScannedWeight += item.netWeight;

        await tallySession.save();

        // Calculate progress
        const expectedItems = await Item.countDocuments({
            status: { $in: ['active', 'booked'] }
        });
        const scannedCount = tallySession.scannedItemIds.length;
        const progress = (scannedCount / expectedItems) * 100;

        res.status(200).json({
            success: true,
            message: 'Item scanned successfully',
            data: {
                item,
                scannedCount,
                expectedCount: expectedItems,
                progress: progress.toFixed(2),
                totalScannedWeight: tallySession.totalScannedWeight,
                expectedTotalWeight: tallySession.expectedTotalWeight
            }
        });
    } catch (error) {
        console.error('Scan item in tally error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while scanning item'
        });
    }
};

// @desc    Lock tally session
// @route   POST /api/tally/lock
// @access  Private
exports.lockTally = async (req, res) => {
    try {
        const { tallySessionId } = req.body;

        if (!tallySessionId) {
            return res.status(400).json({
                success: false,
                message: 'Please provide tally session ID'
            });
        }

        const tallySession = await TallySession.findById(tallySessionId)
            .populate('scannedItemIds', 'name barcode netWeight itemType metalType')
            .populate('excludedItems.itemId', 'name barcode status');

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        if (tallySession.status === 'locked') {
            return res.status(400).json({
                success: false,
                message: 'Tally session is already locked'
            });
        }

        // Find missing items
        const expectedItems = await Item.find({
            status: { $in: ['active', 'booked'] }
        });

        const scannedIds = tallySession.scannedItemIds.map(item =>
            item._id ? item._id.toString() : item.toString()
        );

        const missingItems = expectedItems.filter(item =>
            !scannedIds.includes(item._id.toString())
        );

        tallySession.missingItems = missingItems.map(item => item._id);

        // Calculate mismatch
        const weightDifference = tallySession.calculateMismatch();

        // Lock the session
        tallySession.status = 'locked';
        tallySession.lockedAt = new Date();

        await tallySession.save();

        res.status(200).json({
            success: true,
            message: 'Tally session locked',
            data: {
                tallySession,
                mismatchDetected: tallySession.mismatchDetected,
                weightDifference: weightDifference.toFixed(3),
                missingItemsCount: missingItems.length,
                missingItems: missingItems.map(item => ({
                    id: item._id,
                    name: item.name,
                    barcode: item.barcode,
                    netWeight: item.netWeight
                }))
            }
        });
    } catch (error) {
        console.error('Lock tally error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while locking tally'
        });
    }
};

// @desc    Get tally session details
// @route   GET /api/tally/:id
// @access  Private
exports.getTallySession = async (req, res) => {
    try {
        const tallySession = await TallySession.findById(req.params.id)
            .populate('scannedItemIds', 'name barcode netWeight itemType metalType status')
            .populate('missingItems', 'name barcode netWeight itemType metalType')
            .populate('excludedItems.itemId', 'name barcode status netWeight')
            .populate('createdBy', 'name');

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        res.status(200).json({
            success: true,
            data: { tallySession }
        });
    } catch (error) {
        console.error('Get tally session error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching tally session'
        });
    }
};

// @desc    Get all tally sessions
// @route   GET /api/tally
// @access  Private
exports.getTallySessions = async (req, res) => {
    try {
        const { status } = req.query;

        const filter = {};
        if (status) filter.status = status;

        const tallySessions = await TallySession.find(filter)
            .populate('createdBy', 'name')
            .sort({ createdAt: -1 })
            .limit(50); // Limit to last 50 sessions

        res.status(200).json({
            success: true,
            count: tallySessions.length,
            data: { tallySessions }
        });
    } catch (error) {
        console.error('Get tally sessions error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching tally sessions'
        });
    }
};
