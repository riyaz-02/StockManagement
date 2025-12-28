const Item = require('../models/Item');
const Container = require('../models/Container');
const RepairLog = require('../models/RepairLog');

// @desc    Send item to repair
// @route   POST /api/repair/send
// @access  Private
exports.sendToRepair = async (req, res) => {
    try {
        const {
            itemId,
            repairType,
            sentTo,
            expectedReturnDate,
            slotReserved,
            remarks
        } = req.body;

        // Validate required fields
        if (!itemId || !repairType || !sentTo || !expectedReturnDate || slotReserved === undefined) {
            return res.status(400).json({
                success: false,
                message: 'Please provide all required fields including slot reservation choice'
            });
        }

        const item = await Item.findById(itemId);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Store original container info
        const originalContainerId = item.containerId;
        const originalSlotNumber = item.slotNumber;

        // Create repair log
        const repairLog = await RepairLog.create({
            itemId,
            repairType,
            sentTo,
            expectedReturnDate: new Date(expectedReturnDate),
            slotReserved,
            originalContainerId,
            originalSlotNumber,
            remarks: remarks || '',
            status: 'repair'
        });

        // Update item status
        item.status = 'repair';
        item.slotReserved = slotReserved;

        // Handle container slot based on reservation choice
        if (originalContainerId && originalSlotNumber) {
            const container = await Container.findById(originalContainerId);

            if (container) {
                const slot = container.slots.find(s => s.slotNumber === originalSlotNumber);

                if (slot) {
                    if (slotReserved) {
                        // Reserve the slot - keep itemId but mark as reserved
                        slot.reserved = true;
                    } else {
                        // Free the slot - remove itemId and unreserve
                        slot.itemId = null;
                        slot.reserved = false;

                        // Remove container assignment from item
                        item.containerId = null;
                        item.slotNumber = null;
                    }

                    await container.save();
                }
            }
        }

        await item.save();

        res.status(201).json({
            success: true,
            message: `Item sent to repair. Slot ${slotReserved ? 'reserved' : 'freed'}.`,
            data: { repairLog, item }
        });
    } catch (error) {
        console.error('Send to repair error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while sending item to repair'
        });
    }
};

// @desc    Return item from repair
// @route   POST /api/repair/return
// @access  Private
exports.returnFromRepair = async (req, res) => {
    try {
        const { repairLogId } = req.body;

        if (!repairLogId) {
            return res.status(400).json({
                success: false,
                message: 'Please provide repair log ID'
            });
        }

        const repairLog = await RepairLog.findById(repairLogId);

        if (!repairLog) {
            return res.status(404).json({
                success: false,
                message: 'Repair log not found'
            });
        }

        if (repairLog.status === 'returned') {
            return res.status(400).json({
                success: false,
                message: 'Item already returned from repair'
            });
        }

        const item = await Item.findById(repairLog.itemId);

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        // Update repair log
        repairLog.status = 'returned';
        repairLog.actualReturnDate = new Date();
        await repairLog.save();

        // Update item status
        item.status = 'active';

        if (repairLog.slotReserved) {
            // Slot was reserved - return to same slot
            item.containerId = repairLog.originalContainerId;
            item.slotNumber = repairLog.originalSlotNumber;
            item.slotReserved = false;

            // Update container slot - unreserve it
            if (repairLog.originalContainerId && repairLog.originalSlotNumber) {
                const container = await Container.findById(repairLog.originalContainerId);

                if (container) {
                    const slot = container.slots.find(s => s.slotNumber === repairLog.originalSlotNumber);

                    if (slot) {
                        slot.reserved = false;
                        await container.save();
                    }
                }
            }
        } else {
            // Slot was freed - need to find new slot
            const containers = await Container.find({
                isActive: true,
                $or: [
                    { allowedItemTypes: item.itemType },
                    { allowedItemTypes: { $size: 0 } }
                ]
            });

            let newContainer = null;
            let newSlot = null;

            for (const container of containers) {
                const availableSlot = container.slots.find(
                    slot => slot.itemId === null && !slot.reserved
                );

                if (availableSlot) {
                    newContainer = container;
                    newSlot = availableSlot;
                    break;
                }
            }

            if (!newContainer) {
                return res.status(400).json({
                    success: false,
                    message: 'No available slot found for returning item. Please create space.'
                });
            }

            // Assign new slot
            item.containerId = newContainer._id;
            item.slotNumber = newSlot.slotNumber;
            item.slotReserved = false;

            // Update container
            newSlot.itemId = item._id;
            await newContainer.save();
        }

        await item.save();

        res.status(200).json({
            success: true,
            message: 'Item returned from repair successfully',
            data: { repairLog, item }
        });
    } catch (error) {
        console.error('Return from repair error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while returning item from repair'
        });
    }
};

// @desc    Get all items in repair
// @route   GET /api/repair
// @access  Private
exports.getRepairItems = async (req, res) => {
    try {
        const { status } = req.query;

        const filter = {};
        if (status) filter.status = status;
        else filter.status = 'repair'; // Default to repair

        const repairLogs = await RepairLog.find(filter)
            .populate('itemId', 'name barcode itemType metalType netWeight')
            .populate('originalContainerId', 'name type')
            .sort({ sentDate: -1 });

        res.status(200).json({
            success: true,
            count: repairLogs.length,
            data: { repairLogs }
        });
    } catch (error) {
        console.error('Get repair items error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching repair items'
        });
    }
};

// @desc    Get repair history for an item
// @route   GET /api/repair/history/:itemId
// @access  Private
exports.getRepairHistory = async (req, res) => {
    try {
        const repairLogs = await RepairLog.find({ itemId: req.params.itemId })
            .sort({ sentDate: -1 });

        res.status(200).json({
            success: true,
            count: repairLogs.length,
            data: { repairLogs }
        });
    } catch (error) {
        console.error('Get repair history error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching repair history'
        });
    }
};
