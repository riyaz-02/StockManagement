/**
 * firebaseAdmin.js — Firebase Admin SDK setup for sending push notifications.
 *
 * Needs backend/config/firebase-service-account.json (downloaded from
 * Firebase Console → Project Settings → Service Accounts → Generate new
 * private key). That file is gitignored — this module simply logs a warning
 * and disables sending if it isn't present yet, rather than crashing the
 * whole server.
 *
 * Uses firebase-admin's modular API (v13+) — there is no more `admin.apps`/
 * `admin.messaging()` namespace object, everything comes from the
 * `firebase-admin/app` and `firebase-admin/messaging` subpaths.
 */

const path = require('path');
const fs = require('fs');
const { initializeApp, cert, getApps, getApp } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');
const logger = require('./logger');

const SERVICE_ACCOUNT_PATH = path.join(__dirname, 'firebase-service-account.json');

let messagingClient = null;
let initialized = false;

function getMessagingClient() {
    if (initialized) return messagingClient;
    initialized = true;

    if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
        logger.warn(
            '[FCM] backend/config/firebase-service-account.json not found — push notifications are disabled until it is added.'
        );
        return null;
    }

    try {
        const app = getApps().length ? getApp() : initializeApp({
            credential: cert(require(SERVICE_ACCOUNT_PATH)),
        });
        messagingClient = getMessaging(app);
        logger.info('[FCM] Firebase Admin SDK initialized.');
        return messagingClient;
    } catch (err) {
        logger.error(`[FCM] Failed to initialize Firebase Admin SDK: ${err.message}`);
        messagingClient = null;
        return null;
    }
}

/**
 * Sends a push notification to a list of FCM device tokens.
 * Silently no-ops (returns a zero-success result) if Firebase isn't configured
 * yet, or if the token list is empty.
 */
async function sendPushToTokens(tokens, { title, body, data = {} }) {
    const cleanTokens = (tokens || []).filter(Boolean);
    if (cleanTokens.length === 0) {
        return { successCount: 0, failureCount: 0, invalidTokens: [] };
    }

    const messaging = getMessagingClient();
    if (!messaging) {
        return { successCount: 0, failureCount: cleanTokens.length, invalidTokens: [], disabled: true };
    }

    // FCM data payloads must be flat string maps
    const stringData = Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
    );

    const response = await messaging.sendEachForMulticast({
        tokens: cleanTokens,
        notification: { title, body },
        data: stringData,
        android: { priority: 'high' },
    });

    const invalidTokens = [];
    response.responses.forEach((res, idx) => {
        if (!res.success) {
            const code = res.error?.code || '';
            if (
                code.includes('registration-token-not-registered') ||
                code.includes('invalid-registration-token')
            ) {
                invalidTokens.push(cleanTokens[idx]);
            }
        }
    });

    return {
        successCount: response.successCount,
        failureCount: response.failureCount,
        invalidTokens,
    };
}

module.exports = { sendPushToTokens };
