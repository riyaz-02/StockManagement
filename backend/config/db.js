/**
 * db.js — Dual MongoDB Connection Manager
 *
 * Connection 1 (primary):  jewellery_stock  → existing app data (Items, Containers, etc.)
 * Connection 2 (shopmanage): shopmanage      → new store management modules
 *                            (Purchases, StockEntries, BulkWeights, GstConfig)
 *
 * Both connections share the same cluster and credentials.
 */

const mongoose = require('mongoose');
const logger = require('./logger');

const mongoOptions = {
    maxPoolSize: 20,
    minPoolSize: 5,
    serverSelectionTimeoutMS: 30000,
    socketTimeoutMS: 45000,
};

// ─── Primary connection (jewellery_stock) ───────────────────────────────────
// This is the default mongoose connection — all existing models use it.
const connectPrimary = async () => {
    const uri = process.env.MONGODB_URI;
    if (!uri) {
        logger.error('❌ MONGODB_URI environment variable is not set!');
        process.exit(1);
    }

    logger.info(`[DB] Connecting to jewellery_stock: ${uri.substring(0, 40)}...`);

    await mongoose.connect(uri, mongoOptions);
    logger.info('✅ [DB] jewellery_stock connected');
    logger.info(`[DB] Primary database: ${mongoose.connection.name}`);
};

// ─── Secondary connection (shopmanage) ─────────────────────────────────────
// A separate mongoose connection for the store management collections.
let shopmanageConnection = null;

const connectShopmanage = async () => {
    const uri = process.env.SHOPMANAGE_DB_URI;
    if (!uri) {
        logger.warn('⚠️  [DB] SHOPMANAGE_DB_URI not set — store management features will be unavailable.');
        return null;
    }

    logger.info(`[DB] Connecting to shopmanage: ${uri.substring(0, 40)}...`);

    shopmanageConnection = mongoose.createConnection(uri, mongoOptions);

    shopmanageConnection.on('connected', () => {
        logger.info(`✅ [DB] shopmanage connected (db: ${shopmanageConnection.name})`);
    });

    shopmanageConnection.on('error', (err) => {
        logger.error('[DB] shopmanage connection error:', err.message);
    });

    shopmanageConnection.on('disconnected', () => {
        logger.warn('[DB] shopmanage disconnected');
    });

    // Wait for connection to be ready
    await shopmanageConnection.asPromise();

    return shopmanageConnection;
};

// ─── Third connection (LGP admin cluster → shopmanage db) ──────────────────
// Holds the legacy web-admin data: customers, staff login users, GST data.
// The app treats this DB as PRODUCTION: routes built on it are read + insert
// only (see controllers/directoryController.js). Never add update/delete
// paths against the pre-existing collections here.
let lgpAdminConnection = null;

const connectLgpAdmin = async () => {
    const uri = process.env.LGP_ADMIN_DB_URI;
    if (!uri) {
        logger.warn('⚠️  [DB] LGP_ADMIN_DB_URI not set — User Directory will be unavailable.');
        return null;
    }

    logger.info('[DB] Connecting to LGP admin cluster...');

    lgpAdminConnection = mongoose.createConnection(uri, {
        ...mongoOptions,
        // Never let Mongoose create indexes/collections on this production DB.
        autoIndex: false,
        autoCreate: false,
    });

    lgpAdminConnection.on('connected', () => {
        logger.info(`✅ [DB] LGP admin connected (db: ${lgpAdminConnection.name})`);
    });
    lgpAdminConnection.on('error', (err) => {
        logger.error('[DB] LGP admin connection error:', err.message);
    });
    lgpAdminConnection.on('disconnected', () => {
        logger.warn('[DB] LGP admin disconnected');
    });

    await lgpAdminConnection.asPromise();
    return lgpAdminConnection;
};

const getLgpAdminConnection = () => {
    if (!lgpAdminConnection) {
        throw new Error('LGP admin connection is not initialized (LGP_ADMIN_DB_URI missing?).');
    }
    return lgpAdminConnection;
};

// ─── Getters ────────────────────────────────────────────────────────────────
const getShopmanageConnection = () => {
    if (!shopmanageConnection) {
        throw new Error('shopmanage connection is not initialized. Call connectShopmanage() first.');
    }
    return shopmanageConnection;
};

// ─── Graceful shutdown ──────────────────────────────────────────────────────
const closeAll = async () => {
    await mongoose.connection.close();
    if (shopmanageConnection) {
        await shopmanageConnection.close();
    }
    if (lgpAdminConnection) {
        await lgpAdminConnection.close();
    }
    logger.info('[DB] All connections closed.');
};

module.exports = {
    connectPrimary,
    connectShopmanage,
    getShopmanageConnection,
    connectLgpAdmin,
    getLgpAdminConnection,
    closeAll,
};
