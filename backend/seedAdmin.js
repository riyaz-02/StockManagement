/**
 * seedAdmin.js — One-time script to create the initial admin user
 *
 * Usage:
 *   node seedAdmin.js
 *
 * Connects to the jewellery_stock DB on the new cluster and creates
 * an admin user with the given credentials. Safe to re-run — it will
 * skip creation if the mobile number already exists.
 */

'use strict';

require('dotenv').config();
const mongoose = require('mongoose');
const User = require('./models/User');

const ADMIN = {
    name: 'Admin',
    mobile: '7029621489',
    password: 'Admin@123',
    role: 'admin',
    language: 'en',
    isActive: true,
};

(async () => {
    try {
        const uri = process.env.MONGODB_URI;
        if (!uri) throw new Error('MONGODB_URI not set in .env');

        console.log(`\n🔌 Connecting to: ${uri.substring(0, 45)}...\n`);
        await mongoose.connect(uri, {
            serverSelectionTimeoutMS: 30000,
        });
        console.log(`✅ Connected  →  DB: ${mongoose.connection.name}\n`);

        // Check for existing user
        const existing = await User.findOne({ mobile: ADMIN.mobile });
        if (existing) {
            console.log(`⚠️  User with mobile ${ADMIN.mobile} already exists.`);
            console.log(`   Name : ${existing.name}`);
            console.log(`   Role : ${existing.role}`);
            console.log(`   ID   : ${existing._id}\n`);
            console.log('No changes made. Exiting.\n');
            process.exit(0);
        }

        // Create admin — password hashed automatically by User pre-save hook
        const admin = await User.create(ADMIN);

        console.log('🎉 Admin user created successfully!\n');
        console.log('┌─────────────────────────────────────┐');
        console.log(`│  Name    : ${admin.name.padEnd(25)}│`);
        console.log(`│  Mobile  : ${admin.mobile.padEnd(25)}│`);
        console.log(`│  Role    : ${admin.role.padEnd(25)}│`);
        console.log(`│  ID      : ${String(admin._id).substring(0, 25)}│`);
        console.log('└─────────────────────────────────────┘\n');
        console.log('Login credentials:');
        console.log(`  Mobile   : ${ADMIN.mobile}`);
        console.log(`  Password : ${ADMIN.password}\n`);

    } catch (err) {
        console.error('\n❌ Error:', err.message);
        process.exit(1);
    } finally {
        await mongoose.connection.close();
        process.exit(0);
    }
})();
