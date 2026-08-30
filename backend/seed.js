const mongoose = require('mongoose');
const dotenv = require('dotenv');
const User = require('./models/User');
const Container = require('./models/Container');
const RolePermission = require('./models/RolePermission');
const { DEFAULT_GRIDS, CONFIGURABLE_ROLES } = require('./config/permissions');

// Load environment variables
dotenv.config();

// Connect to MongoDB
mongoose.connect(process.env.MONGODB_URI, {
    useNewUrlParser: true,
    useUnifiedTopology: true
})
    .then(() => console.log('✅ MongoDB connected'))
    .catch((err) => {
        console.error('❌ MongoDB connection error:', err);
        process.exit(1);
    });

const seedDatabase = async () => {
    try {
        console.log('🌱 Seeding database...');

        // Create default admin user
        const adminExists = await User.findOne({ mobile: '9999999999' });

        if (!adminExists) {
            await User.create({
                name: 'Admin',
                mobile: '9999999999',
                password: 'admin123',
                role: 'admin',
                language: 'en'
            });
            console.log('✅ Admin user created (Mobile: 9999999999, Password: admin123)');
        } else {
            console.log('ℹ️  Admin user already exists');
        }

        // Create sample staff user
        const staffExists = await User.findOne({ mobile: '8888888888' });

        if (!staffExists) {
            await User.create({
                name: 'Staff User',
                mobile: '8888888888',
                password: 'staff123',
                role: 'staff',
                language: 'en'
            });
            console.log('✅ Staff user created (Mobile: 8888888888, Password: staff123)');
        } else {
            console.log('ℹ️  Staff user already exists');
        }

        // Create sample containers
        const containerCount = await Container.countDocuments();

        if (containerCount === 0) {
            await Container.create([
                {
                    name: 'Ring Box 1',
                    type: 'ring_box',
                    allowedItemTypes: ['ring'],
                    capacity: 20,
                    weightCategory: 'light',
                    layoutType: 'grid'
                },
                {
                    name: 'Necklace Tray 1',
                    type: 'necklace_tray',
                    allowedItemTypes: ['necklace', 'chain'],
                    capacity: 15,
                    weightCategory: 'heavy',
                    layoutType: 'linear'
                },
                {
                    name: 'Earring Tray 1',
                    type: 'earring_tray',
                    allowedItemTypes: ['earring'],
                    capacity: 25,
                    weightCategory: 'light',
                    layoutType: 'grid'
                },
                {
                    name: 'Mixed Jewelry Box',
                    type: 'custom',
                    allowedItemTypes: [],
                    capacity: 30,
                    weightCategory: 'mixed',
                    layoutType: 'grid'
                }
            ]);
            console.log('✅ Sample containers created');
        } else {
            console.log('ℹ️  Containers already exist');
        }

        // Create default RolePermission grids for manager/staff/viewer
        // (the permission cache already falls back to these defaults in
        // memory even without this step, but persisting them lets the
        // admin see/edit real documents right away in the Permission
        // Manager screen instead of implicit defaults).
        for (const role of CONFIGURABLE_ROLES) {
            const exists = await RolePermission.findOne({ role });
            if (!exists) {
                await RolePermission.create({ role, permissions: DEFAULT_GRIDS[role] });
                console.log(`✅ Default permissions seeded for role: ${role}`);
            } else {
                console.log(`ℹ️  Permissions for role "${role}" already exist`);
            }
        }

        console.log('🎉 Database seeding completed!');
        console.log('\n📝 Login credentials:');
        console.log('   Admin - Mobile: 9999999999, Password: admin123');
        console.log('   Staff - Mobile: 8888888888, Password: staff123');

        process.exit(0);
    } catch (error) {
        console.error('❌ Seeding error:', error);
        process.exit(1);
    }
};

seedDatabase();
