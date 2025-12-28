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
            huid,
            images,
            containerId,
            slotNumber
        } = req.body;

        // Validate required fields
        if (!name || !itemType || !metalType || !purity || !netWeight) {
            return res.status(400).json({
                success: false,
                message: 'Please provide all required fields'
            });
        }

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

        let assignedContainerId = containerId;
        let assignedSlotNumber = slotNumber;

        // Auto-assign container and slot if not provided
        if (!containerId || !slotNumber) {
            const containers = await Container.find({
                isActive: true,
                $or: [
                    { allowedItemTypes: itemType },
                    { allowedItemTypes: { $size: 0 } }
                ]
            });

            // Determine weight category
            let weightCategory = 'light';
            if (netWeight > 10) weightCategory = 'heavy';
            else if (netWeight > 5) weightCategory = 'medium';

            let bestContainer = null;
            let bestSlot = null;

            for (const container of containers) {
                const availableSlot = container.slots.find(
                    slot => slot.itemId === null && !slot.reserved
                );

                if (availableSlot) {
                    if (container.weightCategory === weightCategory || container.weightCategory === 'mixed') {
                        bestContainer = container;
                        bestSlot = availableSlot;
                        break;
                    } else if (!bestContainer) {
                        bestContainer = container;
                        bestSlot = availableSlot;
                    }
                }
            }

            if (!bestContainer) {
                return res.status(400).json({
                    success: false,
                    message: 'No available slot found. Please create a new container.'
                });
            }

            assignedContainerId = bestContainer._id;
            assignedSlotNumber = bestSlot.slotNumber;
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
            huid,
            images: images || [],
            containerId: assignedContainerId,
            slotNumber: assignedSlotNumber,
            status: 'active'
        });

        // Update container slot
        const container = await Container.findById(assignedContainerId);
        const slot = container.slots.find(s => s.slotNumber === assignedSlotNumber);
        slot.itemId = item._id;
        await container.save();

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

// @desc    Get all items
// @route   GET /api/items
// @access  Private
exports.getItems = async (req, res) => {
    try {
        const { status, itemType, metalType, containerId } = req.query;

        const filter = {};
        if (status) filter.status = status;
        if (itemType) filter.itemType = itemType;
        if (metalType) filter.metalType = metalType;
        if (containerId) filter.containerId = containerId;

        const items = await Item.find(filter)
            .populate({
                path: 'containerId',
                select: 'name type',
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
            .populate('containerId', 'name type layoutType');

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
            .populate('containerId', 'name type layoutType');

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

        const {
            name,
            description,
            itemType,
            metalType,
            purity,
            netWeight,
            huid,
            images,
            status
        } = req.body;

        // Update fields
        if (name) item.name = name;
        if (description !== undefined) item.description = description;
        if (itemType) item.itemType = itemType;
        if (metalType) item.metalType = metalType;
        if (purity) item.purity = purity;
        if (netWeight) item.netWeight = netWeight;
        if (huid !== undefined) item.huid = huid;
        if (images) item.images = images;
        if (status) item.status = status;

        await item.save();

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

// @desc    Delete item (admin only)
// @route   DELETE /api/items/:id
// @access  Private/Admin
exports.deleteItem = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

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

        await item.deleteOne();

        res.status(200).json({
            success: true,
            message: 'Item deleted successfully'
        });
    } catch (error) {
        console.error('Delete item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while deleting item'
        });
    }
};

// @desc    Mark item as sold
// @route   PUT /api/items/:id/sell
// @access  Private
exports.sellItem = async (req, res) => {
    try {
        const item = await Item.findById(req.params.id);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Update status to sold
        item.status = 'sold';

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

        res.status(200).json({
            success: true,
            message: 'Item marked as sold',
            data: { item }
        });
    } catch (error) {
        console.error('Sell item error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while selling item'
        });
    }
};

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
