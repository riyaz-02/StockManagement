const Item = require('../models/Item');
const Container = require('../models/Container');
const { nanoid } = require('nanoid');

// Generate unique barcode if not provided
const generateBarcode = async () => {
    // Generate 5 random digits (10000-99999)
    // This gives us 90,000 possible unique codes
    let barcode;
    let exists = true;

    // Keep generating until we find a unique one
    while (exists) {
        // Generate random 5-digit number
        barcode = String(Math.floor(10000 + Math.random() * 90000));

        // Check if it already exists
        const existingItem = await Item.findOne({ barcode });
        exists = !!existingItem;
    }

    return barcode;
};

// @desc    Create new item
// @route   POST /api/items
// @access  Private
// Optional billing detail sent with an item (only what was sent is changed)
const NUM_EXTRAS = ['grossWeight', 'lessWeight', 'stoneValue', 'makingCharge', 'wastage', 'custWastage', 'labourRate', 'makingRate'];
const TXT_EXTRAS = ['stoneNote', 'supplier', 'size'];
function pickExtras(body) {
    const out = {};
    for (const k of NUM_EXTRAS) {
        if (body[k] === undefined) continue;
        if (body[k] === null || body[k] === '' || body[k] === 'null') { out[k] = null; continue; }
        const n = Number(body[k]);
        if (Number.isFinite(n) && n >= 0) out[k] = n;
    }
    for (const k of TXT_EXTRAS) if (body[k] !== undefined) out[k] = String(body[k] || '').trim().slice(0, 120);
    return out;
}


// For clients that do not hold the price rules (the website): `autoMaking: true` makes the server work out the making charge
// billing pre-fills = labour + making (Stock Setting rules) + an optional fixed making (`fixedMaking`).
async function applyAutoMaking(body, extra) {
    if (!(body.autoMaking === true || body.autoMaking === 'true' || body.autoMaking === '1')) return;
    const Rules = require('../services/stockRules');
    const stored = await require('../models/AppStockSettings').findOne({ key: 'main' }).lean();
    const price = require('../services/stockValuation').computeStock({
        net: body.netWeight, gross: body.grossWeight, less: body.lessWeight, purity: body.purity, wastage: body.wastage, labourRate: body.labourRate, makingRate: body.makingRate,
    }, Rules.resolve(stored));
    const total = Math.round((price.makingForBilling + (Number(body.fixedMaking) || 0)) * 100) / 100;
    extra.makingCharge = total > 0 ? total : null;
}

// Free the box slot an item occupies (used when it moves)
async function freeItemSlot(item) {
    if (!item.containerId || !item.slotNumber) return;
    const c = await Container.findById(item.containerId);
    if (!c) return;
    const slot = c.slots.find((s) => s.slotNumber === item.slotNumber);
    if (slot && String(slot.itemId) === String(item._id)) { slot.itemId = null; slot.reserved = false; await c.save(); }
}

exports.createItem = async (req, res) => {
    try {
        const {
            barcode,
            name,
            description,
            itemType,
            metalType,
            purity,
            netWeight,
            numberOfPieces,
            weightCategory,
            weightAccuracy,
            certificationType,
            huidNumber,
            images,
            containerId,
            slotNumber,
            status
        } = req.body;
        const extra = pickExtras(req.body);
        await applyAutoMaking(req.body, extra);

        // Helper to extract images
        let imagePaths = [];
        if (req.files && req.files.length > 0) {
            imagePaths = req.files.map(file => file.path); // Save relative path or full path
        }

        // Also handle if images are passed as text (e.g. existing URLs or JSON string)
        if (images) {
            let existingImages;
            // Parse if it's a JSON string
            if (typeof images === 'string') {
                try {
                    existingImages = JSON.parse(images);
                } catch (e) {
                    existingImages = [images];
                }
            } else {
                existingImages = Array.isArray(images) ? images : [images];
            }
            imagePaths = [...imagePaths, ...existingImages];
        }

        // Validate required fields
        if (!name || !itemType || !metalType || !purity || !netWeight) {
            return res.status(400).json({
                success: false,
                message: 'Please provide all required fields'
            });
        }

        // weight class from the net weight when the client did not choose one
        const wClass = weightCategory || (Number(netWeight) > 10 ? 'Heavy' : Number(netWeight) > 5 ? 'Medium' : 'Light');

        // Generate barcode if not provided
        const itemBarcode = barcode || await generateBarcode();

        // Check if barcode already exists
        const existingItem = await Item.findOne({ barcode: itemBarcode });
        if (existingItem) {
            return res.status(400).json({
                success: false,
                message: 'Item with this barcode already exists'
            });
        }

        let assignedContainerId = containerId || null;
        let assignedSlotNumber = slotNumber || null;

        // Try to auto-assign a container only when one hasn't been explicitly provided
        // This is best-effort: if no container is available the item is saved without one
        if (!containerId || !slotNumber) {
            // boxes of the branch the item is being filed under only (an admin sees every branch)
            const branchNow = (require('../utils/branchScope').current() || {}).branchId || 'main';
            const containers = await Container.find({
                isActive: true,
                $and: [
                    require('../utils/branchScope').matchFor([branchNow]),
                    { $or: [{ allowedItemTypes: itemType }, { allowedItemTypes: { $size: 0 } }] }
                ]
            });

            // Determine weight category for matching
            let wCat = 'light';
            if (netWeight > 10) wCat = 'heavy';
            else if (netWeight > 5) wCat = 'medium';

            let bestContainer = null;
            let bestSlot = null;

            for (const container of containers) {
                const availableSlot = container.slots.find(
                    slot => slot.itemId === null && !slot.reserved
                );
                if (availableSlot) {
                    if (container.weightCategory === wCat || container.weightCategory === 'mixed') {
                        bestContainer = container;
                        bestSlot = availableSlot;
                        break;
                    } else if (!bestContainer) {
                        bestContainer = container;
                        bestSlot = availableSlot;
                    }
                }
            }

            // Assign only if a suitable container was found — no hard error if not
            if (bestContainer) {
                assignedContainerId = bestContainer._id;
                assignedSlotNumber = bestSlot.slotNumber;
            }
            // else: item saves without a container (status can be set to action_needed by caller)
        }

        // Create item
        const item = await Item.create({
            barcode: itemBarcode,
            name,
            description,
            itemType,
            metalType,
            purity,
            netWeight,
            numberOfPieces: numberOfPieces || 1,
            weightCategory: wClass,
            weightAccuracy: weightAccuracy || 'exact',
            certificationType: certificationType || 'none',
            huidNumber: huidNumber || null,
            images: imagePaths,
            containerId: assignedContainerId,
            slotNumber: assignedSlotNumber,
            status: status || 'active',
            ...extra
        });

        // Update container slot
        if (assignedContainerId && assignedSlotNumber) {
            const container = await Container.findById(assignedContainerId);
            if (container) {
                const slot = container.slots.find(s => s.slotNumber === assignedSlotNumber);
                if (slot) {
                    slot.itemId = item._id;
                    await container.save();
                }
            }
        }

        require('../services/audit').record(req, 'stock_item', item._id, `${item.name} (${item.barcode})`, 'created', [{ field: 'metal', to: `${item.metalType} ${item.purity}` }, { field: 'net weight', to: String(item.netWeight) }]);
        res.status(201).json({
            success: true,
            message: 'Item created successfully',
            data: { item }
        });
    } catch (error) {
        console.error('Create item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while creating item'
        });
    }
};

// @desc    Get available filter options
// @route   GET /api/items/filter-options
// @access  Private
exports.getFilterOptions = async (req, res) => {
    try {
        const [metalTypes, itemTypes, purities, weightRange] = await Promise.all([
            Item.distinct('metalType', { status: { $ne: 'deleted' } }),
            Item.distinct('itemType', { status: { $ne: 'deleted' } }),
            Item.distinct('purity', { status: { $ne: 'deleted' } }),
            Item.aggregate([
                { $match: { status: { $ne: 'deleted' } } },
                {
                    $group: {
                        _id: null,
                        minWeight: { $min: '$netWeight' },
                        maxWeight: { $max: '$netWeight' }
                    }
                }
            ])
        ]);

        res.status(200).json({
            success: true,
            data: {
                metalTypes: metalTypes.filter(Boolean).sort(),
                itemTypes: itemTypes.filter(Boolean).sort(),
                purities: purities.filter(Boolean).sort(),
                weightRange: weightRange[0] || { minWeight: 0, maxWeight: 100 }
            }
        });
    } catch (error) {
        console.error('Get filter options error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching filter options'
        });
    }
};

// @desc    Get all items
// @route   GET /api/items
// @access  Private
exports.getItems = async (req, res) => {
    try {
        const { status, itemType, metalType, containerId, search, purity, certificationType } = req.query;

        const filter = {};

        // By default, exclude deleted items unless explicitly requested
        if (status) {
            // Support comma-separated status values
            if (status.includes(',')) {
                const statusArray = status.split(',').map(s => s.trim());
                filter.status = { $in: statusArray };
                console.log(`[GET ITEMS] Multiple statuses: ${statusArray.join(', ')}`);
            } else {
                filter.status = status;
            }
        } else {
            filter.status = { $ne: 'deleted' };
        }

        if (itemType) filter.itemType = itemType;
        if (metalType) filter.metalType = metalType;
        if (containerId) filter.containerId = containerId;
        if (purity) filter.purity = purity;
        if (certificationType) filter.certificationType = certificationType;

        // Weight range filtering
        if (req.query.minWeight || req.query.maxWeight) {
            filter.netWeight = {};
            if (req.query.minWeight) {
                filter.netWeight.$gte = parseFloat(req.query.minWeight);
            }
            if (req.query.maxWeight) {
                filter.netWeight.$lte = parseFloat(req.query.maxWeight);
            }
        }

        // Search functionality - search in name and barcode
        if (search && search.trim()) {
            const searchRegex = new RegExp(search.trim(), 'i');
            filter.$or = [
                { name: searchRegex },
                { barcode: searchRegex }
            ];
            console.log(`[GET ITEMS] Search query: "${search}"`);
        }

        // optional paging (the website): ?limit=&page= returns one page plus the totals of the whole filter
        const limit = Math.min(200, parseInt(req.query.limit, 10) || 0);
        if (limit > 0) {
            const page = Math.max(1, parseInt(req.query.page, 10) || 1);
            const [items, total, sums] = await Promise.all([
                Item.find(filter).populate({ path: 'containerId', select: 'name type qrCode', strictPopulate: false })
                    .sort({ createdAt: -1 }).skip((page - 1) * limit).limit(limit).lean(),
                Item.countDocuments(filter),
                Item.find(filter).select('netWeight').lean(),
            ]);
            return res.status(200).json({
                success: true, count: items.length, data: { items },
                pagination: { page, limit, total, hasMore: page * limit < total }, totals: { count: total, netWeight: Math.round(sums.reduce((a, x) => a + (Number(x.netWeight) || 0), 0) * 1000) / 1000 },
            });
        }

        const items = await Item.find(filter)
            .populate({
                path: 'containerId',
                select: 'name type qrCode',
                strictPopulate: false
            })
            .sort({ createdAt: -1 })
            .lean();

        res.status(200).json({
            success: true,
            count: items.length,
            data: { items }
        });
    } catch (error) {
        console.error('Get items error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching items',
            error: error.message
        });
    }
};

// @desc    Get item by barcode
// @route   GET /api/items/barcode/:code
// @access  Private
exports.getItemByBarcode = async (req, res) => {
    try {
        const item = await Item.findOne({ barcode: req.params.code })
            .populate('containerId', 'name type layoutType qrCode');

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        res.status(200).json({
            success: true,
            data: { item }
        });
    } catch (error) {
        console.error('Get item by barcode error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching item'
        });
    }
};

// @desc    Get single item
// @route   GET /api/items/:id
// @access  Private
exports.getItem = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id)
            .populate('containerId', 'name type layoutType qrCode image');

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        res.status(200).json({
            success: true,
            data: { item }
        });
    } catch (error) {
        console.error('Get item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching item'
        });
    }
};

// @desc    Update item
// @route   PUT /api/items/:id
// @access  Private
exports.updateItem = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }
        const before = { name: item.name, metalType: item.metalType, purity: item.purity, netWeight: item.netWeight, status: item.status, makingCharge: item.makingCharge };

        const {
            name,
            description,
            itemType,
            metalType,
            purity,
            netWeight,
            numberOfPieces,
            weightCategory,
            weightAccuracy,
            certificationType,
            huidNumber,
            images,
            status,
            barcode,
            keptImages,
            containerId: newContainerId,
            slotNumber: newSlotNumber
        } = req.body;
        const extra = pickExtras(req.body);
        await applyAutoMaking(req.body, extra);



        console.log('Update Item Request Body:', req.body);
        console.log('Update Item Files:', req.files);
        console.log('Kept Images Type:', typeof keptImages);
        console.log('Kept Images Value:', keptImages);

        // Check barcode uniqueness if changed
        if (barcode && barcode !== item.barcode) {
            const existingItem = await Item.findOne({ barcode });
            if (existingItem) {
                return res.status(400).json({
                    success: false,
                    message: 'Barcode already exists'
                });
            }
            item.barcode = barcode;
        }

        // Handle Images: Merge kept existing images + new uploaded images
        // Priority: images field (new Cloudinary URLs) > keptImages > req.files
        if (images !== undefined) {
            // New approach: images field contains all Cloudinary URLs as JSON string
            let finalImages = [];
            if (typeof images === 'string') {
                try {
                    finalImages = JSON.parse(images);
                } catch (e) {
                    finalImages = [images];
                }
            } else if (Array.isArray(images)) {
                finalImages = images;
            }
            console.log('Using images field:', finalImages);
            item.images = finalImages;
        } else if (keptImages !== undefined || (req.files && req.files.length > 0)) {
            // Legacy approach for backward compatibility
            let finalImages = [];

            // 1. Process kept images
            if (keptImages) {
                try {
                    let parsed;
                    if (typeof keptImages === 'string') {
                        // Attempt JSON parse first
                        try {
                            parsed = JSON.parse(keptImages);
                        } catch (e) {
                            // If parse fails, treat as single URL string
                            parsed = [keptImages];
                        }
                    } else if (Array.isArray(keptImages)) {
                        parsed = keptImages;
                    } else {
                        parsed = [];
                    }

                    // Ensure flattened array
                    if (Array.isArray(parsed)) {
                        finalImages.push(...parsed);
                    } else if (typeof parsed === 'string') {
                        finalImages.push(parsed);
                    }
                    console.log('Parsed Kept Images:', finalImages);
                } catch (e) {
                    console.warn('Error processing keptImages:', e);
                }
            } else if (keptImages === '') {
                // Explicitly empty string means clear kept images
                console.log('keptImages is empty string, clearing.');
            }

            // 2. Process new uploaded images
            if (req.files && req.files.length > 0) {
                const newImagePaths = req.files.map(file => file.path);
                finalImages.push(...newImagePaths);
                console.log('Added New Images:', newImagePaths);
            }

            console.log('Final Images to Save:', finalImages);
            item.images = finalImages;
        }

        // Update fields
        if (name) item.name = name;
        if (description !== undefined) item.description = description;
        if (itemType) item.itemType = itemType;
        if (metalType) item.metalType = metalType;
        if (purity) item.purity = purity;
        if (netWeight) item.netWeight = netWeight;
        if (numberOfPieces) item.numberOfPieces = numberOfPieces;
        if (weightCategory) item.weightCategory = weightCategory;
        if (weightAccuracy) item.weightAccuracy = weightAccuracy;
        if (certificationType !== undefined) item.certificationType = certificationType;
        if (huidNumber !== undefined) item.huidNumber = huidNumber;
        if (status) item.status = status;
        Object.assign(item, extra);

        // Move to another box / slot (or take out of a box) only when the app asked for it
        if (newContainerId !== undefined) {
            const wantId = newContainerId ? String(newContainerId) : null;
            const wantSlot = newSlotNumber ? Number(newSlotNumber) : null;
            const sameBox = (item.containerId ? String(item.containerId) : null) === wantId;
            if (!sameBox || (wantId && wantSlot && wantSlot !== item.slotNumber)) {
                if (wantId) {
                    const target = await Container.findById(wantId);
                    if (!target || target.isActive === false || target.isDeleted) {
                        return res.status(400).json({ success: false, message: 'That box is not available' });
                    }
                    if (target.isLocked) {
                        return res.status(400).json({ success: false, message: 'That box is locked' });
                    }
                    const slot = wantSlot
                        ? target.slots.find((s) => s.slotNumber === wantSlot)
                        : target.slots.find((s) => !s.itemId && !s.reserved);
                    if (!slot || (slot.itemId && String(slot.itemId) !== String(item._id)) || slot.reserved) {
                        return res.status(400).json({ success: false, message: 'No free slot in that box' });
                    }
                    await freeItemSlot(item);
                    slot.itemId = item._id;
                    await target.save();
                    item.containerId = target._id;
                    item.slotNumber = slot.slotNumber;
                } else {
                    await freeItemSlot(item);
                    item.containerId = null;
                    item.slotNumber = null;
                }
            }
        }

        await item.save();

        const changed = ['name', 'metalType', 'purity', 'netWeight', 'status', 'makingCharge']
            .filter((k) => String(before[k] ?? '') !== String(item[k] ?? ''))
            .map((k) => ({ field: k, from: before[k], to: item[k] }));
        if (changed.length) require('../services/audit').record(req, 'stock_item', item._id, `${item.name} (${item.barcode})`, 'updated', changed);

        res.status(200).json({
            success: true,
            message: 'Item updated successfully',
            data: { item }
        });
    } catch (error) {
        console.error('Update item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while updating item'
        });
    }
};

// @desc    Delete item (Soft Delete)
// @route   DELETE /api/items/:id
// @access  Private/Admin
// Soft-delete an already-fetched Item document: frees its container slot,
// sets status to 'deleted', and clears its location. Shared by the item
// recycle-bin flow and the tally "remove unscanned item" flow.
const softDeleteItemDoc = async (item) => {
    if (item.containerId && item.slotNumber) {
        const container = await Container.findById(item.containerId);
        if (container) {
            const slot = container.slots.find(s => s.slotNumber === item.slotNumber);
            if (slot) {
                slot.itemId = null;
                slot.reserved = false;
                await container.save();
            }
        }
    }

    item.status = 'deleted';
    item.containerId = null;
    item.slotNumber = null;
    await item.save();

    return item;
};

exports.softDeleteItemDoc = softDeleteItemDoc;

exports.deleteItem = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        await softDeleteItemDoc(item);
        require('../services/audit').record(req, 'stock_item', item._id, `${item.name} (${item.barcode})`, 'removed', []);

        res.status(200).json({
            success: true,
            message: 'Item moved to recycle bin'
        });
    } catch (error) {
        console.error('Delete item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while deleting item'
        });
    }
};

// Selling a piece is done on a GST bill (POST /api/billing/invoices): saving the bill marks the piece sold. There is no separate
// "quick sale" record any more (it duplicated the invoice).

// @desc    Temporarily remove item
// @route   PUT /api/items/:id/remove-temporarily
// @access  Private
exports.removeTemporarily = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Update status
        item.status = 'temporarily_removed';

        // Free up container slot
        if (item.containerId && item.slotNumber) {
            const container = await Container.findById(item.containerId);
            if (container) {
                const slot = container.slots.find(s => s.slotNumber === item.slotNumber);
                if (slot) {
                    slot.itemId = null;
                    slot.reserved = false;
                    await container.save();
                }
            }
        }

        item.containerId = null;
        item.slotNumber = null;

        await item.save();
        require('../services/audit').record(req, 'stock_item', item._id, `${item.name} (${item.barcode})`, 'taken out temporarily', []);

        res.status(200).json({
            success: true,
            message: 'Item temporarily removed',
            data: { item }
        });
    } catch (error) {
        console.error('Remove item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while removing item'
        });
    }
};

// @desc    Restore deleted item
// @route   PUT /api/items/:id/restore
// @access  Private
exports.restoreItem = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        if (item.status !== 'deleted') {
            return res.status(400).json({
                success: false,
                message: 'Item is not deleted'
            });
        }

        // Restore item to active status
        item.status = 'active';
        await item.save();
        require('../services/audit').record(req, 'stock_item', item._id, `${item.name} (${item.barcode})`, 'restored', [{ field: 'status', from: 'deleted', to: 'active' }]);

        res.status(200).json({
            success: true,
            message: 'Item restored successfully',
            data: { item }
        });
    } catch (error) {
        console.error('Restore item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while restoring item'
        });
    }
};

// @desc    Permanently delete item
// @route   DELETE /api/items/:id/permanent
// @access  Private/Admin
exports.permanentDeleteItem = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Delete images from Cloudinary before deleting item
        if (item.images && item.images.length > 0) {
            const { deleteCloudinaryImages } = require('../utils/cloudinaryHelper');
            const deletedCount = await deleteCloudinaryImages(item.images);
            console.log(`🗑️ Deleted ${deletedCount}/${item.images.length} images from Cloudinary`);
        }

        // Permanently delete the item from database
        require('../services/audit').record(req, 'stock_item', item._id, `${item.name} (${item.barcode})`, 'permanently deleted', []);
        await Item.findByIdAndDelete(req.params.id);

        res.status(200).json({
            success: true,
            message: 'Item and associated images permanently deleted'
        });
    } catch (error) {
        console.error('Permanent delete item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while permanently deleting item'
        });
    }
};

// @desc    Mark item as no sell
// @route   PUT /api/items/:id/mark-no-sell
// @access  Private
exports.markAsNoSell = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Don't allow marking sold or deleted items as no_sell
        if (item.status === 'sold' || item.status === 'deleted') {
            return res.status(400).json({
                success: false,
                message: `Cannot mark ${item.status} items as no sell`
            });
        }

        const wasStatus = item.status;
        item.status = 'no_sell';
        await item.save();
        require('../services/audit').record(req, 'stock_item', item._id, `${item.name} (${item.barcode})`, 'marked not for sale', [{ field: 'status', from: wasStatus, to: 'no_sell' }]);

        console.log(`✓ Item ${item.barcode} marked as no sell`);

        res.json({
            success: true,
            data: item,
            message: 'Item marked as no sell successfully'
        });
    } catch (error) {
        console.error('Mark as no sell error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while marking item as no sell'
        });
    }
};

// @desc    Mark item as active (remove no sell status)
// @route   PUT /api/items/:id/mark-active
// @access  Private
exports.markAsActive = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        const wasStatus2 = item.status;
        item.status = 'active';
        await item.save();
        require('../services/audit').record(req, 'stock_item', item._id, `${item.name} (${item.barcode})`, 'put back in stock', [{ field: 'status', from: wasStatus2, to: 'active' }]);

        console.log(`✓ Item ${item.barcode} marked as active`);

        res.json({
            success: true,
            data: item,
            message: 'Item marked as active successfully'
        });
    } catch (error) {
        console.error('Mark as active error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while marking item as active'
        });
    }
};

