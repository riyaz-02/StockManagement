const Container = require('../models/Container');
const Item = require('../models/Item');

// @desc    Create new container
// @route   POST /api/containers
// @access  Private/Admin
exports.createContainer = async (req, res) => {
    try {
        const { name, type, allowedItemTypes, capacity, weightCategory, layoutType } = req.body;

        // Validate required fields
        if (!name || !type || !capacity) {
            return res.status(400).json({
                success: false,
                message: 'Please provide name, type, and capacity'
            });
        }

        const container = await Container.create({
            name,
            type,
            allowedItemTypes: allowedItemTypes || [],
            capacity,
            weightCategory: weightCategory || 'mixed',
            layoutType: layoutType || 'grid'
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
exports.getContainers = async (req, res) => {
    try {
        const { isActive, type } = req.query;

        const filter = {};
        if (isActive !== undefined) filter.isActive = isActive === 'true';
        if (type) filter.type = type;

        const containers = await Container.find(filter)
            .populate('slots.itemId', 'name barcode netWeight status')
            .sort({ createdAt: -1 });

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

        res.status(200).json({
            success: true,
            data: { container }
        });
    } catch (error) {
        console.error('Get container error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching container'
        });
    }
};

// @desc    Update container
// @route   PUT /api/containers/:id
// @access  Private/Admin
exports.updateContainer = async (req, res) => {
    try {
        const { name, allowedItemTypes, weightCategory, layoutType, isActive } = req.body;

        const container = await Container.findById(req.params.id);

        if (!container) {
            return res.status(404).json({
                success: false,
                message: 'Container not found'
            });
        }

        // Update fields
        if (name) container.name = name;
        if (allowedItemTypes) container.allowedItemTypes = allowedItemTypes;
        if (weightCategory) container.weightCategory = weightCategory;
        if (layoutType) container.layoutType = layoutType;
        if (isActive !== undefined) container.isActive = isActive;

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

// @desc    Delete container
// @route   DELETE /api/containers/:id
// @access  Private/Admin
exports.deleteContainer = async (req, res) => {
    try {
        const container = await Container.findById(req.params.id);

        if (!container) {
            return res.status(404).json({
                success: false,
                message: 'Container not found'
            });
        }

        // Check if container has items
        const hasItems = container.slots.some(slot => slot.itemId !== null);

        if (hasItems) {
            return res.status(400).json({
                success: false,
                message: 'Cannot delete container with items. Please remove all items first.'
            });
        }

        await container.deleteOne();

        res.status(200).json({
            success: true,
            message: 'Container deleted successfully'
        });
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
