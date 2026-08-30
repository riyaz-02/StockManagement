/**
 * scheduledNotifications.js — first pass at automatic push notifications
 * (GST filing reminder, weekly stock check). More triggers can be added to
 * the JOBS list below later.
 *
 * IMPORTANT CAVEAT: the EC2 backend auto-stops after ~25 idle minutes (see
 * AWS_COST_SAVING_README.md). node-cron only fires while this process is
 * actually running, so an exact-time schedule can't be guaranteed. Instead,
 * each job records its own lastRunAt (ScheduledJobState) and is checked
 * hourly *and* once immediately on boot — if a run was missed while the
 * server was asleep, it fires as soon as the server is next up, rather than
 * being silently skipped for the whole period.
 */

const cron = require('node-cron');
const logger = require('./logger');
const Notification = require('../models/Notification');
const ScheduledJobState = require('../models/ScheduledJobState');
const { sendPushToTokens } = require('./firebaseAdmin');
const { resolveTargetTokens, pruneInvalidTokens } = require('../controllers/notificationController');

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

const JOBS = [
    {
        name: 'gst-reminder',
        title: 'GST Filing Reminder',
        body: "Reminder: file this month's GST return.",
        // Due on the 1st of the month, once per month.
        shouldRun: (now, lastRunAt) => {
            if (now.getDate() !== 1) return false;
            if (!lastRunAt) return true;
            return (
                lastRunAt.getMonth() !== now.getMonth() ||
                lastRunAt.getFullYear() !== now.getFullYear()
            );
        },
    },
    {
        name: 'weekly-stock-check',
        title: 'Weekly Stock Check',
        body: 'Reminder: run this week\'s stock reconciliation check.',
        // Due every Monday, once per week.
        shouldRun: (now, lastRunAt) => {
            if (now.getDay() !== 1) return false;
            if (!lastRunAt) return true;
            return now.getTime() - lastRunAt.getTime() >= 6 * ONE_DAY_MS;
        },
    },
];

async function runJobIfDue(job) {
    const now = new Date();
    const state = await ScheduledJobState.findOne({ jobName: job.name });
    const lastRunAt = state?.lastRunAt || null;

    if (!job.shouldRun(now, lastRunAt)) return;

    const tokens = await resolveTargetTokens({ targetType: 'role', targetRole: 'admin' });
    const result = await sendPushToTokens(tokens, {
        title: job.title,
        body: job.body,
        data: { source: job.name },
    });
    await pruneInvalidTokens(result.invalidTokens);

    await Notification.create({
        title: job.title,
        body: job.body,
        targetType: 'role',
        targetRole: 'admin',
        source: job.name,
        successCount: result.successCount,
        failureCount: result.failureCount,
    });

    await ScheduledJobState.findOneAndUpdate(
        { jobName: job.name },
        { jobName: job.name, lastRunAt: now },
        { upsert: true }
    );

    logger.info(`[Scheduler] Ran "${job.name}" (${result.successCount} delivered, ${result.failureCount} failed)`);
}

function checkAllJobs() {
    JOBS.forEach(job => {
        runJobIfDue(job).catch(err => {
            logger.error(`[Scheduler] Job "${job.name}" failed: ${err.message}`);
        });
    });
}

function startScheduledNotifications() {
    // Catch up immediately on boot, then re-check hourly while running.
    checkAllJobs();
    cron.schedule('0 * * * *', checkAllJobs);
    logger.info('[Scheduler] Automatic notification jobs registered.');
}

module.exports = { startScheduledNotifications };
