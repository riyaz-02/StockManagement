// Database Migration Script
// Run this script to add weightAccuracy field to all existing items

const mongoose = require('mongoose');
const dotenv = require('dotenv');

// Load environment variables from .env file
dotenv.config();

// MongoDB connection string from .env
const MONGODB_URI = process.env.MONGODB_URI;

if (!MONGODB_URI) {
    console.error('❌ Error: MONGODB_URI not found in .env file');
    process.exit(1);
}

async function migrateWeightAccuracy() {
    try {
        console.log('Connecting to MongoDB...');
        await mongoose.connect(MONGODB_URI);
        console.log('✓ Connected to MongoDB');

        const db = mongoose.connection.db;
        const itemsCollection = db.collection('items');

        // Count items without weightAccuracy
        const itemsToMigrate = await itemsCollection.countDocuments({
            weightAccuracy: { $exists: false }
        });

        console.log(`\nFound ${itemsToMigrate} items to migrate`);

        if (itemsToMigrate === 0) {
            console.log('No items need migration. All items already have weightAccuracy field.');
            await mongoose.connection.close();
            return;
        }

        // Update all items without weightAccuracy to have 'exact' as default
        const result = await itemsCollection.updateMany(
            { weightAccuracy: { $exists: false } },
            {
                $set: {
                    weightAccuracy: 'exact',
                    lastVerifiedWeight: null,
                    lastVerifiedAt: null
                }
            }
        );

        console.log(`\n✓ Migration complete!`);
        console.log(`  - Modified ${result.modifiedCount} items`);
        console.log(`  - All items now have weightAccuracy = 'exact'`);
        console.log(`  - Added lastVerifiedWeight and lastVerifiedAt fields`);

        // Verify migration
        const verifyCount = await itemsCollection.countDocuments({
            weightAccuracy: { $exists: true }
        });

        console.log(`\n✓ Verification: ${verifyCount} items now have weightAccuracy field`);

        await mongoose.connection.close();
        console.log('\n✓ Database connection closed');
        console.log('\nMigration successful! You can now use the weight accuracy feature.');

    } catch (error) {
        console.error('\n✗ Migration failed:', error);
        process.exit(1);
    }
}

// Run migration
console.log('='.repeat(60));
console.log('Weight Accuracy Migration Script');
console.log('='.repeat(60));
console.log('\nThis script will add weightAccuracy field to all existing items');
console.log('Default value: "exact"\n');

migrateWeightAccuracy();
