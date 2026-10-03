/**
 * db.js — MongoDB connection
 *
 * ONE database holds everything: the website's `shopmanage` (its customers, users, invoices ...) plus the app's own
 * collections (`items`, `containers`, `app_*` ...), so the phone app, the new website and the old website all work on the
 * same records. MONGODB_URI is the only address, and it must end with the database name (.../shopmanage). There is one
 * connection: `mongoose.connection`, returned by getConnection().
 *
 * Collections the PHP website owns are never created or re-indexed by this app: their models say `autoIndex: false,
 * autoCreate: false` (see models/User.js, models/directory/*), and raw reads/writes go through getConnection().db.
 *
 * The old split layout (a separate app database) is gone; docs/DB_UNIFICATION.md has the design and the merge steps.
 */

const mongoose = require('mongoose');
const logger = require('./logger');

const mongoOptions = {
    maxPoolSize: 20,
    minPoolSize: 5,
    serverSelectionTimeoutMS: 30000,
    socketTimeoutMS: 45000,
};

/** The host part of an address, for logs: never the user name or password. */
const hostOf = (uri) => String(uri).replace(/^mongodb(\+srv)?:\/\//i, '').replace(/^[^@/]*@/, '').split(/[/?]/)[0];

/** The database name an address ends with ('' when it has none). */
const dbNameOf = (uri) => {
    const m = String(uri).match(/^mongodb(?:\+srv)?:\/\/[^/]*\/([^?]*)/i);
    return m ? decodeURIComponent(m[1]) : '';
};

const connectPrimary = async () => {
    const uri = process.env.MONGODB_URI;
    if (!uri) {
        logger.error('❌ MONGODB_URI environment variable is not set!');
        process.exit(1);
    }
    if (!dbNameOf(uri)) {
        // without a name Mongo would silently use a database called "test"
        logger.error('❌ MONGODB_URI must end with the database name, e.g. ...mongodb.net/shopmanage?retryWrites=true');
        process.exit(1);
    }

    logger.info(`[DB] Connecting to ${hostOf(uri)} ...`);
    await mongoose.connect(uri, mongoOptions);
    logger.info(`✅ [DB] connected (database: ${mongoose.connection.name})`);
};

/** The one connection. Every model and every raw collection read goes through it. */
const getConnection = () => mongoose.connection;

const closeAll = async () => {
    await mongoose.connection.close();
    logger.info('[DB] Connection closed.');
};

module.exports = { connectPrimary, getConnection, closeAll, dbNameOf, hostOf };
