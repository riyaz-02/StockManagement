/**
 * Notification.js — log of push notifications sent from the app (manual
 * admin sends, plus automatic/scheduled ones from config/scheduledNotifications.js).
 */

const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema(
    {
        title: {
            type: String,
            required: true,
            trim: true,
        },
        body: {
            type: String,
            required: true,
            trim: true,
        },
        data: {
            type: Object,
            default: {},
        },
        targetType: {
            type: String,
            enum: ['all', 'role'],
            required: true,
            default: 'all',
        },
        targetRole: {
            type: String,
            enum: ['admin', 'staff', 'viewer', null],
            default: null,
        },
        // 'manual' — sent by an admin from the app; anything else names the
        // automatic job that triggered it (e.g. 'gst-reminder').
        source: {
            type: String,
            default: 'manual',
        },
        sentBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
            default: null,
        },
        successCount: {
            type: Number,
            default: 0,
        },
        failureCount: {
            type: Number,
            default: 0,
        },
    },
    { timestamps: true }
);

notificationSchema.index({ createdAt: -1 });

module.exports = mongoose.model('Notification', notificationSchema);
