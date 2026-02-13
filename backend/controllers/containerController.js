const Container = require('../models/Container');
const fs = require('fs');
const path = require('path');
const Item = require('../models/Item');

// @desc    Create new container
// @desc    Create new container
// @route   POST /api/containers
// @access  Private/Admin
exports.createContainer = async (req, res) => {
    try {
        const { name, type, allowedItemTypes, capacity, weightCategory, layoutType, image, metalType, purity, qrCode } = req.body;

        // Validate required fields
        if (!name || !type || !capacity) {
            return res.status(400).json({
                success: false,
                message: 'Please provide name, type, and capacity'
            });
        }

        // Validate barcode is provided
        if (!qrCode || qrCode.trim() === '') {
            return res.status(400).json({
                success: false,
                message: 'Barcode is required'
            });
        }

        // Check if qrCode already exists in database (including deleted containers)
        const existingContainer = await Container.findOne({ qrCode: qrCode.trim() });
        if (existingContainer) {
            return res.status(400).json({
                success: false,
                message: `Barcode "${qrCode}" is already in use${existingContainer.isDeleted ? ' by a deleted container' : ''}. Please generate a new barcode.`
            });
        }

        const container = await Container.create({
            name,
            type,
            allowedItemTypes: allowedItemTypes || [],
            capacity,
            weightCategory: weightCategory || 'mixed',
            layoutType: layoutType || 'grid',
            qrCode: qrCode.trim(),
            image,
            metalType: metalType || [],
            purity: purity || []
        });

        res.status(201).json({
            success: true,
            message: 'Container created successfully',
            data: { container }
        });
    } catch (error) {
        console.error('Create container error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while creating container'
        });
    }
};


// @desc    Get all containers
// @route   GET /api/containers
// @access  Private
// @desc    Get all containers
// @route   GET /api/containers
// @access  Private
exports.getContainers = async (req, res) => {
    try {
        const { isActive, type, isDeleted } = req.query;

        // Default to isDeleted: false unless explicitly requested
        const filter = {};
        if (isDeleted !== undefined) {
            filter.isDeleted = isDeleted === 'true';
        } else {
            filter.isDeleted = false;
        }

        if (isActive !== undefined) filter.isActive = isActive === 'true';
        if (type) filter.type = type;

        const containers = await Container.find(filter)
            .populate('slots.itemId', 'name barcode netWeight status')
            .sort({ createdAt: -1 })
            .lean();

        res.status(200).json({
            success: true,
            count: containers.length,
            data: { containers }
        });
    } catch (error) {
        console.error('Get containers error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching containers'
        });
    }
};

// ... (getContainer remains same)

// @desc    Update container
// @route   PUT /api/containers/:id
// @access  Private/Admin
exports.updateContainer = async (req, res) => {
    try {
        const { name, type, allowedItemTypes, weightCategory, layoutType, isActive, qrCode, capacity, isDeleted, image } = req.body;

        const container = await Container.findById(req.params.id);

        if (!container) {
            return res.status(404).json({
                success: false,
                message: 'Container not found'
            });
        }

        // Update fields
        if (name) container.name = name;
        if (type) container.type = type;
        if (allowedItemTypes) container.allowedItemTypes = allowedItemTypes;
        if (weightCategory) container.weightCategory = weightCategory;
        if (layoutType) container.layoutType = layoutType;
        if (isActive !== undefined) container.isActive = isActive;
        if (qrCode !== undefined) container.qrCode = qrCode;
        if (image !== undefined) {
            // Delete old image if it exists and is different
            if (container.image && container.image !== image) {
                console.log('Old image value:', container.image);
                try {
                    // Remove '/api/uploads/' prefix if present to get just the filename
                    const filename = container.image.replace('/api/uploads/', '');
                    if (filename && !filename.includes('/')) {
                        const oldImagePath = path.join(__dirname, '../uploads', filename);
                        console.log('Attempting to delete old image:', oldImagePath);

                        if (fs.existsSync(oldImagePath)) {
                            fs.unlinkSync(oldImagePath);
                            console.log('Deleted old image successfully');
                        } else {
                            console.log('Old image file not found at:', oldImagePath);
                        }
                    }
                } catch (err) {
                    console.error('Failed to delete old image (continuing update):', err);
                }
            }
            container.image = image;
        }
        if (isDeleted !== undefined) container.isDeleted = isDeleted;
        // eslint-disable-next-line no-prototype-builtins
        if (req.body.hasOwnProperty('isLocked')) container.isLocked = req.body.isLocked;

        // Handle capacity change (same as before)
        if (capacity && capacity > 0 && capacity !== container.capacity) {
            if (capacity > container.capacity) {
                // Increase capacity: Add new slots
                const oldCapacity = container.capacity;
                for (let i = oldCapacity + 1; i <= capacity; i++) {
                    container.slots.push({
                        slotNumber: i,
                        itemId: null,
                        reserved: false
                    });
                }
                container.capacity = capacity;
            } else {
                // Decrease capacity: Check if slots to be removed are empty
                const slotsToRemove = container.slots.slice(capacity);
                const hasItems = slotsToRemove.some(slot => slot.itemId !== null);

                if (hasItems) {
                    return res.status(400).json({
                        success: false,
                        message: 'Cannot reduce capacity. Some slots to be removed contain items.'
                    });
                }

                // Remove slots
                container.slots = container.slots.slice(0, capacity);
                container.capacity = capacity;
            }
        }

        await container.save();

        res.status(200).json({
            success: true,
            message: 'Container updated successfully',
            data: { container }
        });
    } catch (error) {
        console.error('Update container error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while updating container'
        });
    }
};

// @desc    Delete container (Soft delete default, Force delete optional)
// @route   DELETE /api/containers/:id
// @access  Private/Admin
exports.deleteContainer = async (req, res) => {
    try {
        const { force } = req.query; // Check for force delete param
        const container = await Container.findById(req.params.id);

        if (!container) {
            return res.status(404).json({
                success: false,
                message: 'Container not found'
            });
        }

        // Check if container has items
        const hasItems = container.slots.some(slot => slot.itemId !== null);

        if (force === 'true') {
            // Hard delete - allow even if items exist (items will be orphaned/logic handled elsewhere or just remain in slots but container gone)
            // Ideally we should clear the items' container reference, but for now we just allow the delete.
            await container.deleteOne();
            res.status(200).json({
                success: true,
                message: 'Container permanently deleted'
            });
        } else {
            // Soft delete - prevent if has items
            if (hasItems) {
                return res.status(400).json({
                    success: false,
                    message: 'Cannot delete container with items. Please remove all items first.'
                });
            }

            container.isDeleted = true;
            container.isActive = false;
            await container.save();

            res.status(200).json({
                success: true,
                message: 'Container moved to trash'
            });
        }
    } catch (error) {
        console.error('Delete container error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while deleting container'
        });
    }
};



// @desc    Find best container for item (auto-assignment logic)
// @route   POST /api/containers/find-slot
// @access  Private
exports.findBestSlot = async (req, res) => {
    try {
        const { itemType, metalType, netWeight } = req.body;

        if (!itemType || !metalType || !netWeight) {
            return res.status(400).json({
                success: false,
                message: 'Please provide itemType, metalType, and netWeight'
            });
        }

        // Determine weight category
        let weightCategory = 'light';
        if (netWeight > 10) weightCategory = 'heavy';
        else if (netWeight > 5) weightCategory = 'medium';

        // Find suitable containers
        const containers = await Container.find({
            isActive: true,
            $or: [
                { allowedItemTypes: itemType },
                { allowedItemTypes: { $size: 0 } } // Empty array means accepts all types
            ]
        });

        // Sort by preference: matching weight category, then available slots
        let bestContainer = null;
        let bestSlot = null;

        for (const container of containers) {
            const availableSlot = container.slots.find(
                slot => slot.itemId === null && !slot.reserved
            );

            if (availableSlot) {
                // Prefer containers with matching weight category
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
            return res.status(404).json({
                success: false,
                message: 'No available slot found. Please create a new container or free up space.'
            });
        }

        res.status(200).json({
            success: true,
            data: {
                containerId: bestContainer._id,
                containerName: bestContainer.name,
                slotNumber: bestSlot.slotNumber
            }
        });
    } catch (error) {
        console.error('Find slot error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while finding slot'
        });
    }
};

// @desc    Upload container image
// @route   POST /api/containers/upload
// @access  Private/Admin
exports.uploadImage = (req, res) => {
    if (!req.file) {
        return res.status(400).json({
            success: false,
            message: 'No file uploaded'
        });
    }

    // Return URL path (assuming /uploads is served statically)
    res.status(200).json({
        success: true,
        message: 'Image uploaded successfully',
        url: `/uploads/${req.file.filename}`
    });
};

// @desc    Get single container
// @route   GET /api/containers/:id
// @access  Private
exports.getContainer = async (req, res) => {
    try {
        const container = await Container.findById(req.params.id)
            .populate('slots.itemId', 'name barcode netWeight status itemType metalType images');

        if (!container) {
            return res.status(404).json({
                success: false,
                message: 'Container not found'
            });
        }

        // Transform slots to include itemImage, itemBarcode, and itemWeight at slot level
        const containerObj = container.toObject();
        containerObj.slots = containerObj.slots.map(slot => {
            if (slot.itemId && typeof slot.itemId === 'object') {
                const itemImage = slot.itemId.images && slot.itemId.images.length > 0
                    ? slot.itemId.images[0]
                    : null;

                return {
                    ...slot,
                    itemBarcode: slot.itemId.barcode || null,
                    itemImage: itemImage,
                    itemWeight: slot.itemId.netWeight || null
                };
            }
            return slot;
        });

        res.status(200).json({
            success: true,
            data: { container: containerObj }
        });
    } catch (error) {
        console.error('Get container error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching container'
        });
    }
};
