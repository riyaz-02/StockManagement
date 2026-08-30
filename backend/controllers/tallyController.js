const TallySession = require('../models/TallySession');
const Item = require('../models/Item');
const Container = require('../models/Container');
const InventorySnapshot = require('../models/InventorySnapshot');
const { softDeleteItemDoc } = require('./itemController');

// @desc    Create new tally session
// @route   POST /api/tally
// @access  Private/Staff/Admin
exports.createTally = async (req, res) => {
    try {
        const {
            date,
            description,
            expectedItems,
            expectedContainers,
            expectedGoldWeight,
            expectedSilverWeight,
            metalData // NEW: Array of {metalType, expectedWeight, expectedItemCount}
        } = req.body;

        // Validate required fields
        if (!description || expectedItems === undefined || expectedContainers === undefined) {
            return res.status(400).json({
                success: false,
                message: 'Please provide all required fields: description, expectedItems, expectedContainers'
            });
        }

        // **DEBUG**: Log total items in database by status
        const totalItems = await Item.countDocuments();
        const statusCounts = {
            active: await Item.countDocuments({ status: 'active' }),
            in_stock: await Item.countDocuments({ status: 'in_stock' }),
            booked: await Item.countDocuments({ status: 'booked' }),
            wishlisted: await Item.countDocuments({ status: 'wishlisted' }),
            sold: await Item.countDocuments({ status: 'sold' }),
            with_customer: await Item.countDocuments({ status: 'with_customer' }),
            repair: await Item.countDocuments({ status: 'repair' })
        };

        console.log('[TALLY CREATE DEBUG] ==================');
        console.log('[TALLY CREATE DEBUG] Total items in DB:', totalItems);
        console.log('[TALLY CREATE DEBUG] Items by status:', statusCounts);

        // Fetch all items that are physically in the rack.
        // action_needed items are quick-adds that are physically present but details pending.
        const allItems = await Item.find({
            status: { $in: ['active', 'action_needed', 'in_stock', 'booked', 'wishlisted'] }
        })
            .select('barcode metalType netWeight status')
            .lean();

        console.log(`[TALLY CREATE DEBUG] Query returned ${allItems.length} items`);
        console.log('[TALLY CREATE DEBUG] Breakdown:', allItems.reduce((acc, item) => {
            acc[item.status] = (acc[item.status] || 0) + 1;
            return acc;
        }, {}));
        console.log('[TALLY CREATE DEBUG] ==================');

        // Prepare items array with scan status
        const itemsArray = allItems.map(item => ({
            itemId: item._id,
            barcode: item.barcode,
            metalType: item.metalType,
            weight: item.netWeight || 0,
            isScanned: false,
            status: item.status  // Keep original status (in_stock, booked, or wishlisted)
        }));

        // Prepare metalData array (use provided data or defaults)
        let metalDataArray = metalData || [];

        // If no metalData provided, create from legacy fields
        if (metalDataArray.length === 0 && (expectedGoldWeight || expectedSilverWeight)) {
            metalDataArray = [];
            if (expectedGoldWeight) {
                metalDataArray.push({
                    metalType: 'gold',
                    expectedWeight: expectedGoldWeight,
                    expectedItemCount: allItems.filter(i => i.metalType?.toLowerCase() === 'gold').length,
                    scannedWeight: 0,
                    scannedItemCount: 0
                });
            }
            if (expectedSilverWeight) {
                metalDataArray.push({
                    metalType: 'silver',
                    expectedWeight: expectedSilverWeight,
                    expectedItemCount: allItems.filter(i => i.metalType?.toLowerCase() === 'silver').length,
                    scannedWeight: 0,
                    scannedItemCount: 0
                });
            }
        }

        // Create tally session
        const tallySession = await TallySession.create({
            date: date || new Date(),
            description,
            expectedItems,
            expectedContainers,
            expectedGoldWeight: expectedGoldWeight || 0,
            expectedSilverWeight: expectedSilverWeight || 0,
            createdBy: req.user.id,
            status: 'active',
            // NEW: Metal data array
            metalData: metalDataArray,
            // NEW: Items array
            items: itemsArray,
            // Initialize counters
            scannedItemsCount: 0,
            scannedGoldWeight: 0,
            scannedSilverWeight: 0,
            outOfStockCount: 0,
            scannedItemIds: [],
            scannedItemDetails: []
        });

        res.status(201).json({
            success: true,
            message: 'Tally session created successfully',
            data: { tallySession }
        });
    } catch (error) {
        console.error('Create tally error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while creating tally session'
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
            .populate('createdBy', 'name email')
            .populate('lockedBy', 'name email')
            .sort({ createdAt: -1 })
            .limit(100); // Last 100 sessions

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

// @desc    Get single tally session
// @route   GET /api/tally/:id
// @access  Private
exports.getTallySession = async (req, res) => {
    try {
        const tallySession = await TallySession.findById(req.params.id)
            .populate('createdBy', 'name email')
            .populate('lockedBy', 'name email')
            .populate({
                path: 'scannedItemDetails.itemId',
                select: 'name barcode netWeight metalType purity itemType images containerId slotNumber'
            })
            .populate({
                path: 'scannedItemDetails.scannedBy',
                select: 'name'
            });

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

// @desc    Scan item in tally
// @route   PUT /api/tally/:id/scan
// @access  Private/Staff/Admin
exports.scanItem = async (req, res) => {
    try {
        const { barcode } = req.body;

        if (!barcode) {
            return res.status(400).json({
                success: false,
                message: 'Please provide barcode'
            });
        }

        const tallySession = await TallySession.findById(req.params.id);

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        // Check if tally is locked
        if (tallySession.status === 'locked' || tallySession.status === 'force_locked') {
            return res.status(400).json({
                success: false,
                message: 'Tally session is locked. Cannot scan more items.'
            });
        }

        // **CHECK 1**: Prevent scanning more items than expected
        console.log(`[SCAN] Tally ${tallySession._id}: ${tallySession.scannedItemsCount}/${tallySession.expectedItems} items scanned`);

        if (tallySession.scannedItemsCount >= tallySession.expectedItems) {
            console.log(`[SCAN] REJECTED: Tally complete (${tallySession.scannedItemsCount}/${tallySession.expectedItems})`);
            return res.status(400).json({
                success: false,
                message: `Tally is complete. All ${tallySession.expectedItems} items have been scanned.`
            });
        }

        // Find item by barcode
        const item = await Item.findOne({ barcode });
        console.log(`[SCAN] Barcode ${barcode} -> Item ${item ? item._id : 'NOT FOUND'}`);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found with this barcode'
            });
        }

        // **CHECK 2**: Validate item is in expected list (if list exists)
        // Only validate if expectedItemIds exists and has items
        if (tallySession.expectedItemIds && tallySession.expectedItemIds.length > 0) {
            const isItemInTally = tallySession.expectedItemIds.some(
                expectedId => expectedId.toString() === item._id.toString()
            );

            if (!isItemInTally) {
                console.log(`[SCAN] REJECTED: Item ${item._id} not in expected list`);
                return res.status(400).json({
                    success: false,
                    message: 'This item is not part of this tally session',
                    data: { item }
                });
            }
        } else {
            console.log(`[SCAN] WARNING: No expectedItemIds list - accepting any item`);
        }

        // **CHECK 3**: Ensure item not already scanned
        if (tallySession.isItemScanned(item._id)) {
            console.log(`[SCAN] REJECTED: Item ${item._id} already scanned`);
            return res.status(400).json({
                success: false,
                message: 'Item already scanned in this tally session',
                isDuplicate: true,
                data: { item }
            });
        }

        // **CHECK 3.5**: Check if weight verification is required
        console.log(`[SCAN] Item weightAccuracy: "${item.weightAccuracy}" (type: ${typeof item.weightAccuracy})`);
        const requiresWeightVerification = item.weightAccuracy && item.weightAccuracy !== 'exact';
        console.log(`[SCAN] requiresWeightVerification: ${requiresWeightVerification}`);

        if (requiresWeightVerification) {
            console.log(`[SCAN] Item ${item._id} requires weight verification (${item.weightAccuracy})`);
            // Return item details for weight verification popup
            return res.status(200).json({
                success: true,
                requiresWeightVerification: true,
                weightAccuracy: item.weightAccuracy,
                message: 'Weight verification required',
                data: {
                    item: {
                        _id: item._id,
                        barcode: item.barcode,
                        name: item.name,
                        metalType: item.metalType,
                        netWeight: item.netWeight,
                        lastVerifiedWeight: item.lastVerifiedWeight,
                        weightAccuracy: item.weightAccuracy
                    }
                }
            });
        }

        // **CHECK 4**: Validate item status — reject out-of-shop items
        // action_needed items are physically in the rack (quick-added), treat same as active.
        const allowedStatuses = ['active', 'action_needed', 'in_stock', 'booked', 'wishlisted'];
        if (!allowedStatuses.includes(item.status)) {
            console.log(`[SCAN] REJECTED: Item ${item._id} has invalid status: ${item.status}`);

            const statusMessages = {
                'sold':              'Item already sold',
                'repair':            'Item is under repair',
                'in_repair':         'Item is under repair',
                'with_customer':     'Item is with customer',
                'out_of_stock':      'Item is out of stock',
                'deleted':           'Item has been deleted',
            };

            const friendlyMessage = statusMessages[item.status] || `Item status: ${item.status}`;

            return res.status(400).json({
                success: false,
                message: friendlyMessage,
                isOutOfStock: true,
                data: { item }
            });
        }

        // Determine if item is out of stock (this should not happen now, but keeping for safety)
        const outOfStockStatuses = ['repair', 'in_repair', 'UNDER_REPAIR',
            'temporarily_removed', 'WITH_CUSTOMER',
            'WITH_AGENT', 'sold'];
        const isOutOfStock = outOfStockStatuses.includes(item.status);

        // **UPDATE 1**: Mark item as scanned in items array
        const itemInTally = tallySession.items.find(
            i => i.itemId.toString() === item._id.toString()
        );
        if (itemInTally) {
            itemInTally.isScanned = true;
            console.log(`[SCAN] Marked item ${item._id} as scanned in items array`);
        }

        // **UPDATE 2**: Update metalData array
        if (!isOutOfStock) {
            const metalType = item.metalType.toLowerCase();
            const metalDataEntry = tallySession.metalData.find(
                md => md.metalType.toLowerCase() === metalType
            );

            if (metalDataEntry) {
                metalDataEntry.scannedWeight += item.netWeight;
                metalDataEntry.scannedItemCount += 1;
                console.log(`[SCAN] Updated metalData for ${metalType}: ${metalDataEntry.scannedWeight}g (${metalDataEntry.scannedItemCount} items)`);
            }
        }

        // **UPDATE 3**: Add to scanned items tracking
        tallySession.scannedItemIds.push(item._id);
        tallySession.scannedItemDetails.push({
            itemId: item._id,
            scannedAt: new Date(),
            scannedBy: req.user.id,
            status: isOutOfStock ? 'out_of_stock' : 'in_stock',
            weight: item.netWeight,
            metalType: item.metalType
        });

        // **UPDATE 4**: Update counters
        tallySession.scannedItemsCount += 1;

        if (isOutOfStock) {
            // Out of stock items don't count towards weight
            tallySession.outOfStockCount += 1;
        } else {
            // Add weight only for in-stock items
            if (item.metalType.toLowerCase() === 'gold') {
                tallySession.scannedGoldWeight += item.netWeight;
            } else if (item.metalType.toLowerCase() === 'silver') {
                tallySession.scannedSilverWeight += item.netWeight;
            }
        }

        // **CRITICAL**: Save with error handling and validation
        try {
            console.log(`[SCAN] Attempting to save tally session...`);
            console.log(`[SCAN] Pre-save state: ${tallySession.scannedItemsCount}/${tallySession.expectedItems} items`);

            const savedTally = await tallySession.save();

            if (!savedTally) {
                throw new Error('Save returned null/undefined');
            }

            console.log(`[SCAN] ✓ Tally session saved successfully`);
            console.log(`[SCAN] Post-save verification: ${savedTally.scannedItemsCount}/${savedTally.expectedItems} items`);
        } catch (saveError) {
            console.error(`[SCAN] ✗ CRITICAL: Failed to save tally session:`, saveError);
            console.error(`[SCAN] Error details:`, {
                name: saveError.name,
                message: saveError.message,
                code: saveError.code,
                stack: saveError.stack
            });

            return res.status(500).json({
                success: false,
                message: 'Failed to save scan to database. Please try again.',
                error: saveError.message,
                data: {
                    barcode,
                    itemId: item._id,
                    tallyId: tallySession._id
                }
            });
        }

        // Calculate progress
        const progress = tallySession.getProgress();

        console.log(`[SCAN] SUCCESS: Item ${item._id} scanned. Progress: ${tallySession.scannedItemsCount}/${tallySession.expectedItems} (${progress}%)`);

        res.status(200).json({
            success: true,
            message: isOutOfStock ? 'Out-of-stock item scanned (weight not added)' : 'Item scanned successfully',
            data: {
                item,
                isOutOfStock,
                scannedCount: tallySession.scannedItemsCount,
                expectedCount: tallySession.expectedItems,
                progress,
                scannedGoldWeight: tallySession.scannedGoldWeight,
                expectedGoldWeight: tallySession.expectedGoldWeight,
                scannedSilverWeight: tallySession.scannedSilverWeight,
                expectedSilverWeight: tallySession.expectedSilverWeight,
                outOfStockCount: tallySession.outOfStockCount
            }
        });
    } catch (error) {
        console.error('Scan item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while scanning item'
        });
    }
};

// @desc    Verify weight for approx/bulk items during tally
// @route   PUT /api/tally/:id/verify-weight
// @access  Private/Staff/Admin
exports.verifyWeight = async (req, res) => {
    try {
        const { itemId, verifiedWeight } = req.body;

        if (!itemId || !verifiedWeight) {
            return res.status(400).json({
                success: false,
                message: 'Please provide itemId and verifiedWeight'
            });
        }

        // Validate weight is positive
        if (verifiedWeight <= 0) {
            return res.status(400).json({
                success: false,
                message: 'Weight must be greater than zero'
            });
        }

        const tallySession = await TallySession.findById(req.params.id);

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        // Check if tally is locked
        if (tallySession.status === 'locked' || tallySession.status === 'force_locked') {
            return res.status(400).json({
                success: false,
                message: 'Tally session is locked. Cannot verify weight.'
            });
        }

        // Find item
        const item = await Item.findById(itemId);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Check if item already scanned
        if (tallySession.isItemScanned(item._id)) {
            return res.status(400).json({
                success: false,
                message: 'Item already scanned in this tally session'
            });
        }

        console.log(`[VERIFY WEIGHT] Item ${item._id}: ${item.netWeight}g → ${verifiedWeight}g`);

        // Update item weight and verification tracking
        item.netWeight = verifiedWeight;
        item.lastVerifiedWeight = verifiedWeight;
        item.lastVerifiedAt = new Date();
        await item.save();

        // Determine if item is out of stock
        const outOfStockStatuses = ['repair', 'in_repair', 'UNDER_REPAIR',
            'temporarily_removed', 'WITH_CUSTOMER',
            'WITH_AGENT', 'sold'];
        const isOutOfStock = outOfStockStatuses.includes(item.status);

        // Mark item as scanned in items array
        const itemInTally = tallySession.items.find(
            i => i.itemId.toString() === item._id.toString()
        );
        if (itemInTally) {
            itemInTally.isScanned = true;
        }

        // Update metalData array
        if (!isOutOfStock) {
            const metalType = item.metalType.toLowerCase();
            const metalDataEntry = tallySession.metalData.find(
                md => md.metalType.toLowerCase() === metalType
            );

            if (metalDataEntry) {
                metalDataEntry.scannedWeight += verifiedWeight;
                metalDataEntry.scannedItemCount += 1;
            }
        }

        // Add to scanned items tracking
        tallySession.scannedItemIds.push(item._id);
        tallySession.scannedItemDetails.push({
            itemId: item._id,
            scannedAt: new Date(),
            scannedBy: req.user.id,
            status: isOutOfStock ? 'out_of_stock' : 'in_stock',
            weight: verifiedWeight,
            weightAccuracy: item.weightAccuracy,
            metalType: item.metalType
        });

        // Update counters
        tallySession.scannedItemsCount += 1;

        if (isOutOfStock) {
            tallySession.outOfStockCount += 1;
        } else {
            // Add weight only for in-stock items
            if (item.metalType.toLowerCase() === 'gold') {
                tallySession.scannedGoldWeight += verifiedWeight;
            } else if (item.metalType.toLowerCase() === 'silver') {
                tallySession.scannedSilverWeight += verifiedWeight;
            }
        }

        // Save tally session
        await tallySession.save();

        // Calculate progress
        const progress = tallySession.getProgress();

        console.log(`[VERIFY WEIGHT] SUCCESS: Item ${item._id} verified at ${verifiedWeight}g. Progress: ${tallySession.scannedItemsCount}/${tallySession.expectedItems}`);

        res.status(200).json({
            success: true,
            message: 'Weight verified and item scanned successfully',
            data: {
                item,
                verifiedWeight,
                scannedCount: tallySession.scannedItemsCount,
                expectedCount: tallySession.expectedItems,
                progress,
                scannedGoldWeight: tallySession.scannedGoldWeight,
                expectedGoldWeight: tallySession.expectedGoldWeight,
                scannedSilverWeight: tallySession.scannedSilverWeight,
                expectedSilverWeight: tallySession.expectedSilverWeight,
                outOfStockCount: tallySession.outOfStockCount
            }
        });
    } catch (error) {
        console.error('Verify weight error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while verifying weight'
        });
    }
};


// @desc    Lock tally session
// @route   PUT /api/tally/:id/lock
// @access  Private/Staff/Admin
exports.lockTally = async (req, res) => {
    try {
        const { remarks } = req.body;

        const tallySession = await TallySession.findById(req.params.id);

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        if (tallySession.status === 'locked' || tallySession.status === 'force_locked') {
            return res.status(400).json({
                success: false,
                message: 'Tally session is already locked'
            });
        }

        // Check if all items are scanned
        const itemsLeft = tallySession.expectedItems - tallySession.scannedItemsCount;
        const isForceLock = itemsLeft > 0;

        if (isForceLock && !remarks) {
            return res.status(400).json({
                success: false,
                message: 'Remarks are required when force locking with unscanned items',
                data: { itemsLeft }
            });
        }

        // Calculate mismatch
        const mismatchInfo = tallySession.calculateMismatch();

        // Lock the session
        tallySession.status = isForceLock ? 'force_locked' : 'locked';
        tallySession.lockedAt = new Date();
        tallySession.lockedBy = req.user.id;
        tallySession.lockRemarks = remarks || '';
        tallySession.isForceLocked = isForceLock;

        await tallySession.save();

        res.status(200).json({
            success: true,
            message: isForceLock ? 'Tally session force locked' : 'Tally session locked successfully',
            data: {
                tallySession,
                mismatchInfo,
                itemsLeft,
                isForceLocked: isForceLock
            }
        });
    } catch (error) {
        console.error('Lock tally error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while locking tally session'
        });
    }
};

// @desc    Get tally report/summary
// @route   GET /api/tally/:id/report
// @access  Private
exports.getTallyReport = async (req, res) => {
    try {
        const tallySession = await TallySession.findById(req.params.id)
            .populate('createdBy', 'name email')
            .populate('lockedBy', 'name email')
            .populate({
                path: 'scannedItemDetails.itemId',
                select: 'name barcode netWeight metalType purity itemType'
            });

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        // Calculate mismatch
        const mismatchInfo = tallySession.calculateMismatch();

        // Separate in-stock and out-of-stock items
        const inStockItems = tallySession.scannedItemDetails.filter(
            detail => detail.status === 'in_stock'
        );
        const outOfStockItems = tallySession.scannedItemDetails.filter(
            detail => detail.status === 'out_of_stock'
        );

        const report = {
            tallyInfo: {
                id: tallySession._id,
                date: tallySession.date,
                description: tallySession.description,
                status: tallySession.status,
                createdBy: tallySession.createdBy,
                lockedBy: tallySession.lockedBy,
                lockedAt: tallySession.lockedAt,
                lockRemarks: tallySession.lockRemarks,
                isForceLocked: tallySession.isForceLocked
            },
            expected: {
                items: tallySession.expectedItems,
                containers: tallySession.expectedContainers,
                goldWeight: tallySession.expectedGoldWeight,
                silverWeight: tallySession.expectedSilverWeight
            },
            scanned: {
                items: tallySession.scannedItemsCount,
                goldWeight: tallySession.scannedGoldWeight,
                silverWeight: tallySession.scannedSilverWeight,
                outOfStockCount: tallySession.outOfStockCount
            },
            mismatch: mismatchInfo,
            progress: tallySession.getProgress(),
            itemsLeft: tallySession.expectedItems - tallySession.scannedItemsCount,
            inStockItems: inStockItems.length,
            outOfStockItems: outOfStockItems.length
        };

        res.status(200).json({
            success: true,
            data: { report }
        });
    } catch (error) {
        console.error('Get tally report error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while generating tally report'
        });
    }
};

// @desc    Get items for a tally session
// @route   GET /api/tally/:id/items
// @access  Private/Staff/Admin
exports.getTallyItems = async (req, res) => {
    try {
        const tallySession = await TallySession.findById(req.params.id);

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        // Get all active items
        const allItems = await Item.find({ status: { $ne: 'deleted' } })
            .select('barcode name netWeight metalType status containerId slotNumber')
            .lean();

        // Mark which items have been scanned
        const scannedIds = new Set(tallySession.scannedItemIds.map(id => id.toString()));

        const itemsWithStatus = allItems.map(item => ({
            ...item,
            isScanned: scannedIds.has(item._id.toString()),
            scanStatus: scannedIds.has(item._id.toString()) ? 'scanned' : 'not_scanned'
        }));

        res.status(200).json({
            success: true,
            data: { items: itemsWithStatus }
        });
    } catch (error) {
        console.error('Get tally items error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching tally items'
        });
    }
};

// @desc    Delete tally session
// @route   DELETE /api/tally/:id
// @access  Private/Admin
exports.deleteTally = async (req, res) => {
    try {
        const tally = await TallySession.findById(req.params.id);

        if (!tally) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        // Permanently delete the tally session
        await TallySession.findByIdAndDelete(req.params.id);

        res.status(200).json({
            success: true,
            message: 'Tally session deleted successfully'
        });
    } catch (error) {
        console.error('Error deleting tally:', error);
        res.status(500).json({
            success: false,
            message: 'Error deleting tally session',
            error: error.message
        });
    }
};

// @desc    Remove a single unscanned item from stock + this tally (soft-delete)
// @route   PUT /api/tally/:id/remove-item
// @access  Private/Admin
exports.removeUnscannedItem = async (req, res) => {
    try {
        const { itemId } = req.body;

        if (!itemId) {
            return res.status(400).json({
                success: false,
                message: 'Please provide itemId'
            });
        }

        const tallySession = await TallySession.findById(req.params.id);

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        if (tallySession.status !== 'active') {
            return res.status(400).json({
                success: false,
                message: 'Tally session is not active'
            });
        }

        if (tallySession.isItemScanned(itemId)) {
            return res.status(400).json({
                success: false,
                message: 'Item already scanned in this tally session, cannot remove'
            });
        }

        const itemInTally = tallySession.items.find(
            i => i.itemId.toString() === itemId.toString()
        );

        if (!itemInTally) {
            return res.status(404).json({
                success: false,
                message: 'Item is not part of this tally session'
            });
        }

        if (itemInTally.status === 'removed') {
            return res.status(400).json({
                success: false,
                message: 'Item already removed from this tally'
            });
        }

        const item = await Item.findById(itemId);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        if (item.status === 'deleted') {
            return res.status(400).json({
                success: false,
                message: 'Item is already deleted'
            });
        }

        await softDeleteItemDoc(item);
        applyUnscannedItemRemoval(tallySession, itemInTally, item);

        await tallySession.save();

        res.status(200).json({
            success: true,
            message: 'Item removed from stock and tally',
            data: {
                tallySession,
                progress: tallySession.getProgress()
            }
        });
    } catch (error) {
        console.error('Remove unscanned item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while removing item'
        });
    }
};

// @desc    Remove all (or a specified subset of) unscanned items from stock + this tally
// @route   PUT /api/tally/:id/remove-unscanned
// @access  Private/Admin
exports.removeAllUnscannedItems = async (req, res) => {
    try {
        const { itemIds } = req.body || {};

        const tallySession = await TallySession.findById(req.params.id);

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        if (tallySession.status !== 'active') {
            return res.status(400).json({
                success: false,
                message: 'Tally session is not active'
            });
        }

        // Default: every currently-unscanned, not-yet-removed item in the session
        let targets = tallySession.items.filter(i => !i.isScanned && i.status !== 'removed');

        if (Array.isArray(itemIds) && itemIds.length > 0) {
            const idSet = new Set(itemIds.map(String));
            targets = targets.filter(i => idSet.has(i.itemId.toString()));
        }

        let removedCount = 0;

        for (const itemInTally of targets) {
            const item = await Item.findById(itemInTally.itemId);
            if (!item || item.status === 'deleted') continue;

            await softDeleteItemDoc(item);
            applyUnscannedItemRemoval(tallySession, itemInTally, item);
            removedCount += 1;
        }

        await tallySession.save();

        res.status(200).json({
            success: true,
            message: `${removedCount} item(s) removed from stock and tally`,
            data: {
                removedCount,
                tallySession,
                progress: tallySession.getProgress()
            }
        });
    } catch (error) {
        console.error('Remove all unscanned items error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while removing items'
        });
    }
};

// Shared bookkeeping for both single and bulk unscanned-item removal.
// Marks the tally-items[] entry removed and shrinks expected counts/weights
// (metalData + legacy gold/silver fields) so a removed item stops being
// counted as "missing" once the tally is locked.
function applyUnscannedItemRemoval(tallySession, itemInTally, item) {
    itemInTally.status = 'removed';

    tallySession.expectedItems = Math.max(0, tallySession.expectedItems - 1);

    const metalType = (item.metalType || '').toLowerCase();
    const weight = item.netWeight || 0;

    const metalDataEntry = tallySession.metalData.find(
        md => md.metalType.toLowerCase() === metalType
    );
    if (metalDataEntry) {
        metalDataEntry.expectedItemCount = Math.max(0, metalDataEntry.expectedItemCount - 1);
        metalDataEntry.expectedWeight = Math.max(0, metalDataEntry.expectedWeight - weight);
    }

    if (metalType === 'gold') {
        tallySession.expectedGoldWeight = Math.max(0, tallySession.expectedGoldWeight - weight);
    } else if (metalType === 'silver') {
        tallySession.expectedSilverWeight = Math.max(0, tallySession.expectedSilverWeight - weight);
    }
}

// @desc    Add a just-created item (forgotten during initial stock entry) into an active tally
// @route   POST /api/tally/:id/add-item
// @access  Private/Staff/Admin
exports.addItemToTally = async (req, res) => {
    try {
        const { barcode } = req.body;

        if (!barcode) {
            return res.status(400).json({
                success: false,
                message: 'Please provide barcode'
            });
        }

        const tallySession = await TallySession.findById(req.params.id);

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        if (tallySession.status !== 'active') {
            return res.status(400).json({
                success: false,
                message: 'Tally session is not active'
            });
        }

        const item = await Item.findOne({ barcode });

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found with this barcode'
            });
        }

        if (tallySession.isItemScanned(item._id)) {
            return res.status(400).json({
                success: false,
                message: 'Item already scanned in this tally session',
                isDuplicate: true
            });
        }

        const weight = item.netWeight || 0;
        const metalType = (item.metalType || '').toLowerCase();

        tallySession.items.push({
            itemId: item._id,
            barcode: item.barcode,
            metalType: item.metalType,
            weight,
            isScanned: true,
            scannedAt: new Date(),
            scannedBy: req.user.id,
            status: 'in_stock'
        });

        tallySession.expectedItems += 1;

        let metalDataEntry = tallySession.metalData.find(
            md => md.metalType.toLowerCase() === metalType
        );
        if (!metalDataEntry) {
            tallySession.metalData.push({
                metalType: item.metalType,
                expectedWeight: 0,
                expectedItemCount: 0,
                scannedWeight: 0,
                scannedItemCount: 0
            });
            metalDataEntry = tallySession.metalData[tallySession.metalData.length - 1];
        }
        metalDataEntry.expectedItemCount += 1;
        metalDataEntry.expectedWeight += weight;
        metalDataEntry.scannedItemCount += 1;
        metalDataEntry.scannedWeight += weight;

        tallySession.scannedItemIds.push(item._id);
        tallySession.scannedItemDetails.push({
            itemId: item._id,
            scannedAt: new Date(),
            scannedBy: req.user.id,
            status: 'in_stock',
            weight,
            metalType: item.metalType
        });

        tallySession.scannedItemsCount += 1;

        if (metalType === 'gold') {
            tallySession.expectedGoldWeight += weight;
            tallySession.scannedGoldWeight += weight;
        } else if (metalType === 'silver') {
            tallySession.expectedSilverWeight += weight;
            tallySession.scannedSilverWeight += weight;
        }

        await tallySession.save();

        const progress = tallySession.getProgress();

        res.status(200).json({
            success: true,
            message: 'Item added to tally',
            data: {
                item,
                tallySession,
                scannedCount: tallySession.scannedItemsCount,
                expectedCount: tallySession.expectedItems,
                progress
            }
        });
    } catch (error) {
        console.error('Add item to tally error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while adding item to tally'
        });
    }
};

// @desc    Generate a saved inventory snapshot from a locked tally
// @route   POST /api/tally/:id/update-inventory
// @access  Private/Staff/Admin
exports.updateInventory = async (req, res) => {
    try {
        const tallySession = await TallySession.findById(req.params.id);

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        if (tallySession.status !== 'locked' && tallySession.status !== 'force_locked') {
            return res.status(400).json({
                success: false,
                message: 'Tally must be locked before updating inventory'
            });
        }

        if (tallySession.inventoryUpdated) {
            return res.status(400).json({
                success: false,
                message: 'Inventory already updated for this tally',
                data: { inventorySnapshotId: tallySession.inventorySnapshotId }
            });
        }

        // Live, post-cleanup inventory: whatever is confirmed in stock right now
        const items = await Item.find({ status: { $in: ['active', 'booked'] } })
            .populate('containerId', 'name')
            .select('barcode name metalType netWeight status containerId slotNumber')
            .lean();

        const byMetalMap = {};
        const containerIds = new Set();

        const snapshotItems = items.map(item => {
            const metalType = (item.metalType || 'other').toLowerCase();
            if (!byMetalMap[metalType]) {
                byMetalMap[metalType] = { metalType, totalWeight: 0, itemCount: 0 };
            }
            byMetalMap[metalType].totalWeight += item.netWeight || 0;
            byMetalMap[metalType].itemCount += 1;

            if (item.containerId?._id) {
                containerIds.add(item.containerId._id.toString());
            }

            return {
                itemId: item._id,
                barcode: item.barcode,
                name: item.name,
                metalType: item.metalType,
                netWeight: item.netWeight,
                containerId: item.containerId?._id || null,
                containerName: item.containerId?.name || null,
                slotNumber: item.slotNumber,
                status: item.status
            };
        });

        const snapshot = await InventorySnapshot.create({
            tallySessionId: tallySession._id,
            date: new Date(),
            createdBy: req.user.id,
            totalItems: snapshotItems.length,
            totalContainers: containerIds.size,
            byMetal: Object.values(byMetalMap).map(m => ({
                ...m,
                totalWeight: parseFloat(m.totalWeight.toFixed(3))
            })),
            items: snapshotItems
        });

        tallySession.inventoryUpdated = true;
        tallySession.inventoryUpdatedAt = new Date();
        tallySession.inventorySnapshotId = snapshot._id;
        await tallySession.save();

        res.status(200).json({
            success: true,
            message: 'Inventory updated successfully',
            data: { snapshot, tallySession }
        });
    } catch (error) {
        console.error('Update inventory error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while updating inventory'
        });
    }
};

module.exports = exports;
