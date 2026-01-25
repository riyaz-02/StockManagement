const Item = require('../models/Item');
const PDFGenerator = require('../utils/pdfGenerator');

// Get all items for tag printing
exports.getItemsForTagPrinting = async (req, res) => {
    try {
        const items = await Item.find({
            status: { $in: ['active', 'booked', 'in_stock'] }
        })
            .populate('containerId', 'name qrCode')
            .populate('lastPrintedBy', 'name')
            .sort({ name: 1 });

        res.status(200).json({
            success: true,
            count: items.length,
            items
        });
    } catch (error) {
        console.error('Error fetching items for tag printing:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch items',
            error: error.message
        });
    }
};

// Record tag print event
exports.recordTagPrint = async (req, res) => {
    try {
        const { itemIds } = req.body;
        const userId = req.user._id;

        if (!itemIds || !Array.isArray(itemIds) || itemIds.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'Item IDs array is required'
            });
        }

        const result = await Item.updateMany(
            { _id: { $in: itemIds } },
            {
                $set: {
                    tagsPrinted: true,
                    lastTagPrintedAt: new Date(),
                    lastPrintedBy: userId
                },
                $inc: { tagPrintCount: 1 }
            }
        );

        res.status(200).json({
            success: true,
            message: `Tag print recorded for ${result.modifiedCount} items`,
            modifiedCount: result.modifiedCount
        });
    } catch (error) {
        console.error('Error recording tag print:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to record tag print',
            error: error.message
        });
    }
};

// Get tag print history for an item
exports.getTagPrintHistory = async (req, res) => {
    try {
        const { itemId } = req.params;

        const item = await Item.findById(itemId)
            .populate('lastPrintedBy', 'name email')
            .select('barcode name tagsPrinted lastTagPrintedAt tagPrintCount lastPrintedBy');

        if (!item) {
            return res.status(404).json({
                success: false,
                message: 'Item not found'
            });
        }

        res.status(200).json({
            success: true,
            history: {
                barcode: item.barcode,
                name: item.name,
                tagsPrinted: item.tagsPrinted,
                lastTagPrintedAt: item.lastTagPrintedAt,
                tagPrintCount: item.tagPrintCount,
                lastPrintedBy: item.lastPrintedBy
            }
        });
    } catch (error) {
        console.error('Error fetching tag print history:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch tag print history',
            error: error.message
        });
    }
};

// Generate PDF for selected items
exports.generateTagsPDF = async (req, res) => {
    try {
        const { itemIds } = req.body;

        console.log(`[PDF Generation] Request received for ${itemIds?.length || 0} items`);

        if (!itemIds || !Array.isArray(itemIds) || itemIds.length === 0) {
            console.log('[PDF Generation] Invalid request: No item IDs provided');
            return res.status(400).json({
                success: false,
                message: 'Item IDs array is required'
            });
        }

        // Fetch items
        const items = await Item.find({ _id: { $in: itemIds } })
            .select('barcode name netWeight purity certificationType huidNumber')
            .lean();

        console.log(`[PDF Generation] Found ${items.length} items in database`);

        if (items.length === 0) {
            console.log('[PDF Generation] No items found for given IDs');
            return res.status(404).json({
                success: false,
                message: 'No items found'
            });
        }

        // Log sample item for debugging
        console.log('[PDF Generation] Sample item:', {
            barcode: items[0].barcode,
            name: items[0].name,
            weight: items[0].netWeight,
            purity: items[0].purity,
            certificationType: items[0].certificationType,
            huidNumber: items[0].huidNumber
        });

        // Generate PDF
        console.log('[PDF Generation] Starting PDF generation...');
        const pdfBuffer = await PDFGenerator.generateTagsPDF(items);
        console.log(`[PDF Generation] PDF generated successfully: ${pdfBuffer.length} bytes`);

        // Set headers for binary PDF
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename=barcode-tags-${Date.now()}.pdf`);
        res.setHeader('Content-Length', pdfBuffer.length);

        // Send raw binary buffer - use res.end() not res.send()
        // res.send() might JSON-encode the buffer
        res.end(pdfBuffer, 'binary');

    } catch (error) {
        console.error('[PDF Generation] Error:', error);
        console.error('[PDF Generation] Stack:', error.stack);
        res.status(500).json({
            success: false,
            message: 'Failed to generate PDF',
            error: error.message
        });
    }
};
