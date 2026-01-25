const mongoose = require('mongoose');
const dotenv = require('dotenv');
const User = require('./models/User');

// Load environment variables
dotenv.config();

// Connect to MongoDB
mongoose.connect(process.env.MONGODB_URI, {
    useNewUrlParser: true,
    useUnifiedTopology: true
})
    .then(() => console.log('✅ MongoDB connected to production database'))
    .catch((err) => {
        console.error('❌ MongoDB connection error:', err);
        process.exit(1);
    });

const addAdminUser = async () => {
    try {
        console.log('👤 Adding admin user to production database...');

        // Check if user already exists
        const existingUser = await User.findOne({ mobile: '7029621489' });

        if (existingUser) {
            console.log('⚠️  User with mobile 7029621489 already exists');
            console.log('   Name:', existingUser.name);
            console.log('   Role:', existingUser.role);

            // Update the existing user
            existingUser.name = 'Sk Riyaz';
            existingUser.password = 'Riyaz@30092002';
            existingUser.role = 'admin';
            existingUser.language = 'en';
            await existingUser.save();

            console.log('✅ User updated successfully!');
        } else {
            // Create new admin user
            await User.create({
                name: 'Sk Riyaz',
                mobile: '7029621489',
                password: 'Riyaz@30092002',
                role: 'admin',
                language: 'en'
            });
            console.log('✅ Admin user created successfully!');
        }

        console.log('\n📝 Admin Login Credentials:');
        console.log('   Mobile: 7029621489');
        console.log('   Password: Riyaz@30092002');
        console.log('   Role: admin');

        process.exit(0);
    } catch (error) {
        console.error('❌ Error adding admin user:', error);
        process.exit(1);
    }
};

addAdminUser();
