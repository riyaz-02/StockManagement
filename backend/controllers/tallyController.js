const TallySession = require('../models/TallySession');
const Item = require('../models/Item');
const Container = require('../models/Container');
const InventorySnapshot = require('../models/InventorySnapshot');
const { softDeleteItemDoc } = require('./itemController');
const Help = require('../services/tallyHelp');

const SHOP_STATUSES = ['active', 'action_needed', 'in_stock', 'booked', 'wishlisted'];

// The pieces of a session with their CURRENT state: where they sit now, and whether they left the shop since the tally began.
async function loadPieces(session) {
    const ids = (session.items || []).map((i) => i.itemId);
    const docs = await Item.find({ _id: { $in: ids } }).select('barcode name netWeight metalType status containerId slotNumber').lean();
    const byId = new Map(docs.map((d) => [String(d._id), d]));
    const boxIds = [...new Set(docs.map((d) => String(d.containerId || '')).filter(Boolean))];
    const boxes = boxIds.length ? await Container.find({ _id: { $in: boxIds } }).select('name').lean() : [];
    const boxName = new Map(boxes.map((b) => [String(b._id), b.name]));
    return (session.items || []).map((i) => {
        const d = byId.get(String(i.itemId)) || {};
        const cid = d.containerId ? String(d.containerId) : '';
        return {
            id: String(i.itemId), barcode: d.barcode || i.barcode, name: d.name || '', metalType: d.metalType || i.metalType, weight: d.netWeight != null ? d.netWeight : i.weight,
            scanned: !!i.isScanned, gone: !d._id || Help.GONE.includes(d.status), status: d.status || 'deleted', containerId: cid, containerName: boxName.get(cid) || '', slot: d.slotNumber || null,
        };
    });
}
const findRow = (p) => ({ itemId: p.id, barcode: p.barcode, name: p.name, metalType: p.metalType, weight: p.weight, box: p.containerName || (p.containerId ? 'Box' : 'Not in any box'), slot: p.slot });

// @desc    Create new tally session
// @route   POST /api/tally
// @access  Private/Staff/Admin
exports.createTally = async (req, res) => {
    try {
        // One tally at a time: two running together only confuses the counting.
        const running = await TallySession.findOne({ status: 'active' }).select('description createdAt').lean();
        if (running) {
            return res.status(409).json({ success: false, message: `A tally is already running ("${running.description}"). Finish or lock it before starting another.`, existingId: running._id });
        }

        // What should be in the shop right now: worked out here from the stock itself (nothing to type, nothing to get wrong).
        const allItems = await Item.find({ status: { $in: SHOP_STATUSES } }).select('barcode metalType netWeight status containerId').lean();
        if (!allItems.length) {
            return res.status(400).json({ success: false, message: 'There is no stock in the shop to tally yet.' });
        }
        const itemsArray = allItems.map((item) => ({ itemId: item._id, barcode: item.barcode, metalType: item.metalType, weight: item.netWeight || 0, isScanned: false, status: item.status }));

        const metals = {};
        for (const it of allItems) {
            const m = String(it.metalType || 'other').toLowerCase();
            metals[m] = metals[m] || { metalType: m, expectedWeight: 0, expectedItemCount: 0, scannedWeight: 0, scannedItemCount: 0 };
            metals[m].expectedWeight = Help.r3(metals[m].expectedWeight + (it.netWeight || 0));
            metals[m].expectedItemCount += 1;
        }
        const containers = new Set(allItems.map((i) => String(i.containerId || '')).filter(Boolean));
        const today = new Date();
        const ist = new Date(today.getTime() + 5.5 * 3600000);
        const description = String((req.body || {}).description || '').trim() || `Stock tally ${String(ist.getUTCDate()).padStart(2, '0')} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][ist.getUTCMonth()]} ${ist.getUTCFullYear()}`;

        const tallySession = await TallySession.create({
            date: today, description,
            expectedItems: allItems.length, expectedContainers: containers.size,
            expectedGoldWeight: (metals.gold || {}).expectedWeight || 0, expectedSilverWeight: (metals.silver || {}).expectedWeight || 0,
            createdBy: req.user.id, status: 'active',
            metalData: Object.values(metals), items: itemsArray, expectedItemIds: allItems.map((i) => i._id),
            scannedItemsCount: 0, scannedGoldWeight: 0, scannedSilverWeight: 0, outOfStockCount: 0, scannedItemIds: [], scannedItemDetails: [],
        });
        res.status(201).json({ success: true, message: 'Tally started', data: { tallySession } });
    } catch (error) {
        console.error('Create tally error:', error);
        res.status(500).json({ success: false, message: 'Server error while creating tally session' });
    }
};

// GET /api/tally/preview : what a new tally would count (the Start screen shows it before anything is created)
exports.previewTally = async (req, res) => {
    try {
        const items = await Item.find({ status: { $in: SHOP_STATUSES } }).select('metalType netWeight containerId').lean();
        const metals = {};
        for (const it of items) {
            const m = String(it.metalType || 'other').toLowerCase();
            metals[m] = metals[m] || { metalType: m, items: 0, weight: 0 };
            metals[m].items += 1;
            metals[m].weight = Help.r3(metals[m].weight + (it.netWeight || 0));
        }
        const running = await TallySession.findOne({ status: 'active' }).select('description').lean();
        res.json({ success: true, data: { items: items.length, containers: new Set(items.map((i) => String(i.containerId || '')).filter(Boolean)).size, metals: Object.values(metals), running: running ? { id: running._id, description: running.description } : null } });
    } catch (e) {
        res.status(500).json({ success: false, message: 'Could not read the stock' });
    }
};

// GET /api/tally/:id/summary : box-by-box progress and the list of pieces still to find (with box and slot)
exports.tallySummary = async (req, res) => {
    try {
        const session = await TallySession.findById(req.params.id);
        if (!session) return res.status(404).json({ success: false, message: 'Tally session not found' });
        if (session.status !== 'active' && (session.missingAtLock || []).length + (session.soldSinceLock || []).length > 0) {
            // a locked tally shows what was recorded at the moment it was locked
            return res.json({ success: true, data: { frozen: true, expected: session.expectedItems, scanned: session.scannedItemsCount, boxes: [], missing: session.missingAtLock, soldSince: session.soldSinceLock } });
        }
        const pieces = await loadPieces(session);
        const rec = Help.reconcile(pieces);
        res.json({ success: true, data: {
            frozen: false,
            expected: rec.expectedItems, scanned: rec.scanned.length, left: rec.missing.length, soldSince: rec.soldSince.map(findRow),
            expectedWeight: rec.expectedWeight, soldWeight: rec.soldWeight,
            boxes: Help.boxProgress(pieces),
            missing: rec.missing.slice(0, 300).map(findRow),
        } });
    } catch (e) {
        console.error('Tally summary error:', e);
        res.status(500).json({ success: false, message: 'Could not work out the tally progress' });
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

        // **CHECK 2b**: the tally is a photograph taken when it started; a piece that is not in it is not counted
        if ((tallySession.items || []).length > 0 && !tallySession.items.some((i) => i.itemId.toString() === item._id.toString())) {
            return res.status(400).json({
                success: false,
                notInTally: true,
                message: `${item.name || item.barcode} was not in stock when this tally started, so it is not counted. Add it with "Add missing item" if it belongs here.`,
                data: { item }
            });
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

        // What is left is worked out from the pieces: a piece sold while the tally ran does not count as missing
        const pieces = await loadPieces(tallySession);
        const rec = Help.reconcile(pieces);
        const itemsLeft = rec.missing.length;
        const isForceLock = itemsLeft > 0;

        if (isForceLock && !remarks) {
            return res.status(400).json({
                success: false,
                message: 'Remarks are required when force locking with unscanned items',
                data: { itemsLeft }
            });
        }
        tallySession.missingAtLock = rec.missing.map(findRow);
        tallySession.soldSinceLock = rec.soldSince.map(findRow);

        // Calculate mismatch
        const mismatchInfo = tallySession.calculateMismatch();
        // pieces sold since the start are not expected on the shelf: take their weight off what was expected
        const goldDiff = Math.abs(tallySession.scannedGoldWeight - (tallySession.expectedGoldWeight - (rec.soldWeight.gold || 0)));
        const silverDiff = Math.abs(tallySession.scannedSilverWeight - (tallySession.expectedSilverWeight - (rec.soldWeight.silver || 0)));
        Object.assign(mismatchInfo, { goldDifference: Help.r3(goldDiff), silverDifference: Help.r3(silverDiff), totalDifference: Help.r3(goldDiff + silverDiff), mismatchDetected: goldDiff + silverDiff > 0.01 });
        tallySession.mismatchDetected = mismatchInfo.mismatchDetected;

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
                missing: tallySession.missingAtLock,
                soldSince: tallySession.soldSinceLock,
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
