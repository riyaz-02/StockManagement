const Item = require('../models/Item');
const TallySession = require('../models/TallySession');
const Booking = require('../models/Booking');
const RepairLog = require('../models/RepairLog');
const PDFDocument = require('pdfkit');
const ExcelJS = require('exceljs');

// @desc    Get daily summary report
// @route   GET /api/reports/daily
// @access  Private
exports.getDailySummary = async (req, res) => {
    try {
        const { date } = req.query;

        // Use provided date or today
        const targetDate = date ? new Date(date) : new Date();
        const startOfDay = new Date(targetDate.setHours(0, 0, 0, 0));
        const endOfDay = new Date(targetDate.setHours(23, 59, 59, 999));

        // active + action_needed are both physically in-shop (action_needed = quick-add pending details)
        const activeItems = await Item.countDocuments({ status: { $in: ['active', 'action_needed'] } });
        const bookedItems = await Item.countDocuments({ status: 'booked' });
        const inRepairItems = await Item.countDocuments({ status: { $in: ['repair', 'in_repair'] } });
        const tempRemovedItems = await Item.countDocuments({ status: 'temporarily_removed' });

        // Items sold today
        const soldToday = await Item.countDocuments({
            status: 'sold',
            updatedAt: { $gte: startOfDay, $lte: endOfDay }
        });

        // Total weight by metal type (active + action_needed + booked — all physically in-shop)
        const weightData = await Item.getTotalWeight({
            status: { $in: ['active', 'action_needed', 'booked'] }
        });

        // Bookings today
        const bookingsToday = await Booking.countDocuments({
            bookingDate: { $gte: startOfDay, $lte: endOfDay },
            status: 'active'
        });

        // Items sent to repair today
        const repairToday = await RepairLog.countDocuments({
            sentDate: { $gte: startOfDay, $lte: endOfDay },
            status: { $in: ['repair', 'in_repair'] }
        });

        // Items returned from repair today
        const returnedToday = await RepairLog.countDocuments({
            actualReturnDate: { $gte: startOfDay, $lte: endOfDay },
            status: 'returned'
        });

        res.status(200).json({
            success: true,
            data: {
                date: targetDate,
                inventory: {
                    active: activeItems,
                    booked: bookedItems,
                    inRepair: inRepairItems,
                    temporarilyRemoved: tempRemovedItems,
                    total: activeItems + bookedItems
                },
                weight: weightData,
                today: {
                    sold: soldToday,
                    bookings: bookingsToday,
                    sentToRepair: repairToday,
                    returnedFromRepair: returnedToday
                }
            }
        });
    } catch (error) {
        console.error('Daily summary error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while generating daily summary'
        });
    }
};

// @desc    Generate tally report PDF
// @route   GET /api/reports/tally/:id/pdf
// @access  Private
exports.generateTallyPDF = async (req, res) => {
    try {
        const tallySession = await TallySession.findById(req.params.id)
            .populate('scannedItemIds', 'name barcode netWeight itemType metalType')
            .populate('missingItems', 'name barcode netWeight itemType metalType')
            .populate('excludedItems.itemId', 'name barcode status netWeight')
            .populate('createdBy', 'name');

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        // Create PDF document
        const doc = new PDFDocument({ margin: 50 });

        // Set response headers
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename=tally-report-${tallySession._id}.pdf`);

        // Pipe PDF to response
        doc.pipe(res);

        // Add content
        doc.fontSize(20).text('Tally Report', { align: 'center' });
        doc.moveDown();

        doc.fontSize(12);
        doc.text(`Date: ${new Date(tallySession.date).toLocaleDateString()}`);
        doc.text(`Created By: ${tallySession.createdBy.name}`);
        doc.text(`Status: ${tallySession.status.toUpperCase()}`);
        doc.text(`Description: ${tallySession.description || 'N/A'}`);
        doc.moveDown();

        // Summary
        doc.fontSize(14).text('Summary', { underline: true });
        doc.fontSize(12);
        doc.text(`Scanned Items: ${tallySession.scannedItemIds.length}`);
        doc.text(`Total Scanned Weight: ${tallySession.totalScannedWeight.toFixed(3)} grams`);
        doc.text(`Expected Total Weight: ${tallySession.expectedTotalWeight.toFixed(3)} grams`);
        doc.text(`Weight Difference: ${Math.abs(tallySession.totalScannedWeight - tallySession.expectedTotalWeight).toFixed(3)} grams`);
        doc.text(`Mismatch Detected: ${tallySession.mismatchDetected ? 'YES' : 'NO'}`);
        doc.moveDown();

        // Weight by metal
        doc.fontSize(14).text('Weight by Metal Type', { underline: true });
        doc.fontSize(12);
        doc.text(`Gold: ${tallySession.weightByMetal.gold.toFixed(3)} grams`);
        doc.text(`Silver: ${tallySession.weightByMetal.silver.toFixed(3)} grams`);
        doc.text(`Platinum: ${tallySession.weightByMetal.platinum.toFixed(3)} grams`);
        doc.text(`Mixed: ${tallySession.weightByMetal.mixed.toFixed(3)} grams`);
        doc.moveDown();

        // Missing items
        if (tallySession.missingItems && tallySession.missingItems.length > 0) {
            doc.fontSize(14).text('Missing Items', { underline: true });
            doc.fontSize(10);
            tallySession.missingItems.forEach((item, index) => {
                doc.text(`${index + 1}. ${item.name} (${item.barcode}) - ${item.netWeight}g`);
            });
            doc.moveDown();
        }

        // Excluded items
        if (tallySession.excludedItems && tallySession.excludedItems.length > 0) {
            doc.fontSize(14).text('Excluded Items (Not Counted)', { underline: true });
            doc.fontSize(10);
            tallySession.excludedItems.forEach((excluded, index) => {
                if (excluded.itemId) {
                    doc.text(`${index + 1}. ${excluded.itemId.name} (${excluded.itemId.barcode}) - ${excluded.reason}`);
                }
            });
        }

        // Finalize PDF
        doc.end();
    } catch (error) {
        console.error('Generate PDF error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while generating PDF'
        });
    }
};

// @desc    Generate tally report Excel
// @route   GET /api/reports/tally/:id/excel
// @access  Private
exports.generateTallyExcel = async (req, res) => {
    try {
        const tallySession = await TallySession.findById(req.params.id)
            .populate('scannedItemIds', 'name barcode netWeight itemType metalType purity')
            .populate('missingItems', 'name barcode netWeight itemType metalType purity')
            .populate('excludedItems.itemId', 'name barcode status netWeight itemType metalType')
            .populate('createdBy', 'name');

        if (!tallySession) {
            return res.status(404).json({
                success: false,
                message: 'Tally session not found'
            });
        }

        // Create workbook
        const workbook = new ExcelJS.Workbook();

        // Summary sheet
        const summarySheet = workbook.addWorksheet('Summary');
        summarySheet.columns = [
            { header: 'Field', key: 'field', width: 30 },
            { header: 'Value', key: 'value', width: 30 }
        ];

        summarySheet.addRows([
            { field: 'Date', value: new Date(tallySession.date).toLocaleDateString() },
            { field: 'Created By', value: tallySession.createdBy.name },
            { field: 'Status', value: tallySession.status.toUpperCase() },
            { field: 'Description', value: tallySession.description || 'N/A' },
            { field: '', value: '' },
            { field: 'Scanned Items', value: tallySession.scannedItemIds.length },
            { field: 'Total Scanned Weight (g)', value: tallySession.totalScannedWeight.toFixed(3) },
            { field: 'Expected Total Weight (g)', value: tallySession.expectedTotalWeight.toFixed(3) },
            { field: 'Weight Difference (g)', value: Math.abs(tallySession.totalScannedWeight - tallySession.expectedTotalWeight).toFixed(3) },
            { field: 'Mismatch Detected', value: tallySession.mismatchDetected ? 'YES' : 'NO' },
            { field: '', value: '' },
            { field: 'Gold Weight (g)', value: tallySession.weightByMetal.gold.toFixed(3) },
            { field: 'Silver Weight (g)', value: tallySession.weightByMetal.silver.toFixed(3) },
            { field: 'Platinum Weight (g)', value: tallySession.weightByMetal.platinum.toFixed(3) },
            { field: 'Mixed Weight (g)', value: tallySession.weightByMetal.mixed.toFixed(3) }
        ]);

        // Scanned items sheet
        const scannedSheet = workbook.addWorksheet('Scanned Items');
        scannedSheet.columns = [
            { header: 'No.', key: 'no', width: 5 },
            { header: 'Barcode', key: 'barcode', width: 15 },
            { header: 'Name', key: 'name', width: 25 },
            { header: 'Type', key: 'type', width: 12 },
            { header: 'Metal', key: 'metal', width: 12 },
            { header: 'Purity', key: 'purity', width: 10 },
            { header: 'Weight (g)', key: 'weight', width: 12 }
        ];

        tallySession.scannedItemIds.forEach((item, index) => {
            scannedSheet.addRow({
                no: index + 1,
                barcode: item.barcode,
                name: item.name,
                type: item.itemType,
                metal: item.metalType,
                purity: item.purity,
                weight: item.netWeight
            });
        });

        // Missing items sheet
        if (tallySession.missingItems && tallySession.missingItems.length > 0) {
            const missingSheet = workbook.addWorksheet('Missing Items');
            missingSheet.columns = [
                { header: 'No.', key: 'no', width: 5 },
                { header: 'Barcode', key: 'barcode', width: 15 },
                { header: 'Name', key: 'name', width: 25 },
                { header: 'Type', key: 'type', width: 12 },
                { header: 'Metal', key: 'metal', width: 12 },
                { header: 'Weight (g)', key: 'weight', width: 12 }
            ];

            tallySession.missingItems.forEach((item, index) => {
                missingSheet.addRow({
                    no: index + 1,
                    barcode: item.barcode,
                    name: item.name,
                    type: item.itemType,
                    metal: item.metalType,
                    weight: item.netWeight
                });
            });
        }

        // Excluded items sheet
        if (tallySession.excludedItems && tallySession.excludedItems.length > 0) {
            const excludedSheet = workbook.addWorksheet('Excluded Items');
            excludedSheet.columns = [
                { header: 'No.', key: 'no', width: 5 },
                { header: 'Barcode', key: 'barcode', width: 15 },
                { header: 'Name', key: 'name', width: 25 },
                { header: 'Reason', key: 'reason', width: 20 },
                { header: 'Weight (g)', key: 'weight', width: 12 }
            ];

            tallySession.excludedItems.forEach((excluded, index) => {
                if (excluded.itemId) {
                    excludedSheet.addRow({
                        no: index + 1,
                        barcode: excluded.itemId.barcode,
                        name: excluded.itemId.name,
                        reason: excluded.reason,
                        weight: excluded.itemId.netWeight
                    });
                }
            });
        }

        // Set response headers
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        res.setHeader('Content-Disposition', `attachment; filename=tally-report-${tallySession._id}.xlsx`);

        // Write to response
        await workbook.xlsx.write(res);
        res.end();
    } catch (error) {
        console.error('Generate Excel error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while generating Excel'
        });
    }
};
