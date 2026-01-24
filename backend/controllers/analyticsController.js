const Item = require('../models/Item');
const Container = require('../models/Container');
const TallySession = require('../models/TallySession');

// Get dashboard analytics stats
exports.getDashboardStats = async (req, res) => {
    try {
        console.log('📊 [Analytics API] Fetching dashboard stats...');

        // DEBUG: Check total items in database (including deleted)
        const totalItemsIncludingDeleted = await Item.countDocuments({});
        console.log(`   🔍 DEBUG - Total items in DB (including deleted): ${totalItemsIncludingDeleted}`);

        // DEBUG: Sample a few items to check their isDeleted status
        const sampleItems = await Item.find({}).limit(5).select('name barcode isDeleted status');
        console.log('   🔍 DEBUG - Sample items:', JSON.stringify(sampleItems, null, 2));

        // Get total items count (not deleted)
        // Use $ne: true to catch items where isDeleted is false, null, or undefined
        const totalItems = await Item.countDocuments({ isDeleted: { $ne: true } });
        console.log(`   Total Items (isDeleted != true): ${totalItems}`);

        // Get items by status - using actual status values from schema
        const itemsByStatus = await Item.aggregate([
            { $match: { isDeleted: { $ne: true } } },
            {
                $group: {
                    _id: '$status',
                    count: { $sum: 1 }
                }
            }
        ]);
        console.log('   Raw status counts:', itemsByStatus);

        // Convert to object format with all possible statuses
        const statusCounts = {
            active: 0,
            booked: 0,
            repair: 0,
            in_repair: 0,
            temporarily_removed: 0,
            sold: 0,
            UNDER_REPAIR: 0,
            WITH_CUSTOMER: 0,
            WITH_AGENT: 0
        };

        itemsByStatus.forEach(item => {
            if (item._id && statusCounts.hasOwnProperty(item._id)) {
                statusCounts[item._id] = item.count;
            }
        });

        // Combine repair statuses for display
        const combinedRepair = statusCounts.repair + statusCounts.in_repair + statusCounts.UNDER_REPAIR;
        console.log(`   Combined Repair Count: ${combinedRepair}`);

        // NEW: Get weight by status
        const weightByStatus = await Item.aggregate([
            { $match: { isDeleted: { $ne: true } } },
            {
                $group: {
                    _id: '$status',
                    totalWeight: { $sum: '$netWeight' },
                    count: { $sum: 1 }
                }
            }
        ]);
        console.log('   Weight by Status:', weightByStatus);

        // Convert weight by status to object format
        const statusWeights = {
            active: 0,
            booked: 0,
            repair: 0,
            in_repair: 0,
            temporarily_removed: 0,
            UNDER_REPAIR: 0
        };

        weightByStatus.forEach(item => {
            if (item._id && statusWeights.hasOwnProperty(item._id)) {
                statusWeights[item._id] = parseFloat((item.totalWeight || 0).toFixed(2));
            }
        });

        // Combine repair weights
        const combinedRepairWeight = statusWeights.repair + statusWeights.in_repair + statusWeights.UNDER_REPAIR;
        const totalWeight = Object.values(statusWeights).reduce((sum, weight) => sum + weight, 0);
        console.log(`   Total Weight: ${totalWeight.toFixed(2)}g, Repair Weight: ${combinedRepairWeight.toFixed(2)}g`);

        // Get total containers count
        const totalContainers = await Container.countDocuments({ isDeleted: false });
        console.log(`   Total Containers: ${totalContainers}`);

        // Get total tallies and active tallies
        const totalTallies = await TallySession.countDocuments();
        const activeTallies = await TallySession.countDocuments({ status: 'active' });
        console.log(`   Total Tallies: ${totalTallies}, Active: ${activeTallies}`);

        // Get CURRENT STOCK by metal (only items physically in shop)
        // Include: active, booked, in_repair, UNDER_REPAIR
        // Exclude: WITH_CUSTOMER, WITH_AGENT, temporarily_removed, sold, deleted
        const currentStockByMetal = await Item.aggregate([
            {
                $match: {
                    isDeleted: { $ne: true },
                    status: { $in: ['active', 'booked', 'in_repair', 'UNDER_REPAIR'] }
                }
            },
            {
                $group: {
                    _id: '$metalType',
                    totalWeight: { $sum: '$netWeight' },
                    count: { $sum: 1 }
                }
            },
            { $sort: { totalWeight: -1 } }
        ]);
        console.log('   Current Stock by Metal:', currentStockByMetal);

        // Convert to array format (3 decimal places)
        const currentStockMetalBreakdown = currentStockByMetal
            .filter(item => item._id)
            .map(item => ({
                metal: item._id,
                weight: parseFloat((item.totalWeight || 0).toFixed(3)),
                count: item.count
            }));

        // Calculate current stock total weight
        const currentStockTotalWeight = currentStockByMetal.reduce((sum, item) => sum + (item.totalWeight || 0), 0);
        const currentStockTotalCount = currentStockByMetal.reduce((sum, item) => sum + (item.count || 0), 0);
        console.log(`   Current Stock Total: ${currentStockTotalWeight.toFixed(3)}g (${currentStockTotalCount} items)`);

        // NEW: Get detailed breakdown by status AND metal type
        const statusMetalBreakdown = await Item.aggregate([
            { $match: { isDeleted: { $ne: true } } },
            {
                $group: {
                    _id: { status: '$status', metal: '$metalType' },
                    totalWeight: { $sum: '$netWeight' },
                    count: { $sum: 1 }
                }
            },
            { $sort: { '_id.status': 1, totalWeight: -1 } }
        ]);
        console.log('   Status-Metal Breakdown:', statusMetalBreakdown);

        // Convert to array format (3 decimal places)
        const detailedBreakdown = statusMetalBreakdown
            .filter(item => item._id.metal && item._id.status)
            .map(item => ({
                status: item._id.status,
                metal: item._id.metal,
                weight: parseFloat((item.totalWeight || 0).toFixed(3)),
                count: item.count
            }));

        // Get sold/deleted items count
        const soldItems = await Item.countDocuments({ isDeleted: true }); // Only count explicitly deleted items
        console.log(`   Sold Items: ${soldItems}`);

        const responseData = {
            totalItems,
            totalWeight: parseFloat(totalWeight.toFixed(3)),
            totalContainers,
            itemsByStatus: {
                active: {
                    count: statusCounts.active,
                    weight: parseFloat(statusWeights.active.toFixed(3))
                },
                out_of_stock: {
                    count: statusCounts.temporarily_removed,
                    weight: parseFloat(statusWeights.temporarily_removed.toFixed(3))
                },
                in_repair: {
                    count: combinedRepair,
                    weight: parseFloat(combinedRepairWeight.toFixed(3))
                },
                booked: {
                    count: statusCounts.booked,
                    weight: parseFloat(statusWeights.booked.toFixed(3))
                }
            },
            totalTallies,
            activeTallies,
            currentStockMetalBreakdown, // Array of { metal, weight, count } - physically in shop
            currentStockTotalWeight: parseFloat(currentStockTotalWeight.toFixed(3)),
            currentStockTotalCount,
            detailedBreakdown, // Array of { status, metal, weight, count } - detailed breakdown
            soldItems
        };

        console.log('✅ [Analytics API] Response data:', JSON.stringify(responseData, null, 2));

        res.json({
            success: true,
            data: responseData
        });
    } catch (error) {
        console.error('❌ [Analytics API] Error fetching dashboard stats:', error);
        res.status(500).json({
            success: false,
            message: 'Error fetching dashboard statistics',
            error: error.message
        });
    }
};
