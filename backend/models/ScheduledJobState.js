/**
 * ScheduledJobState.js — tracks the last successful run of each named
 * automatic-notification job (config/scheduledNotifications.js), so a
 * missed run (e.g. the EC2 instance was auto-stopped) can be caught up
 * the next time the server is actually running, instead of silently lost.
 */

const mongoose = require('mongoose');

const scheduledJobStateSchema = new mongoose.Schema({
    jobName: {
        type: String,
        required: true,
        unique: true,
    },
    lastRunAt: {
        type: Date,
        default: null,
    },
});

module.exports = mongoose.model('ScheduledJobState', scheduledJobStateSchema);
