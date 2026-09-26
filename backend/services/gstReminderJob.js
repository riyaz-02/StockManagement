/**
 * gstReminderJob.js — sends the GST due-date reminders (push to the admins) and remembers what was sent.
 *
 * Called hourly and once on boot by config/scheduledNotifications.js. The EC2 server may be asleep on the exact
 * day, so a reminder fires as soon as its lead time has been reached (see gstReports.pendingReminders), once.
 */
'use strict';
const logger = require('../config/logger');
const G = require('./gstReports');
const Notification = require('../models/Notification');
const { GstFiling, GstReminderLog } = require('../models/AppGst');
const { sendPushToTokens } = require('../config/firebaseAdmin');

/**
 * One pass per registration (GSTIN): each has its own filing frequency, due dates and filed returns. Reminder keys of
 * a registration other than the firm's default carry a "<GSTIN>#" prefix so they never clash.
 */
async function runGstReminders(now = new Date()) {
    const { _loadSettings, _filingFilter } = require('../controllers/gstReportsController');
    const { resolveTargetTokens, pruneInvalidTokens } = require('../controllers/notificationController');
    const { loadRegistrations } = require('./registrations');
    const regs = await loadRegistrations();
    const today = G.istYmd(now);
    const sent = new Set((await GstReminderLog.find({}).select('key').lean()).map((x) => x.key));
    let total = 0;
    for (const reg of regs) {
        const { settings } = await _loadSettings(reg);
        if (settings.reminders.enabled === false) continue;
        const prefix = reg.isDefault ? '' : `${reg.gstin}#`;
        const mine = new Set([...sent].filter((k) => (prefix ? k.startsWith(prefix) : !k.includes('#'))).map((k) => k.slice(prefix.length)));
        const filings = await GstFiling.find(_filingFilter(reg)).lean();
        const due = G.pendingReminders(settings, filings, today, mine);
        if (!due.length) continue;
        const tokens = await resolveTargetTokens({ targetType: 'role', targetRole: 'admin' });
        const tag = regs.length > 1 ? ` (${reg.gstin})` : '';
        for (const r of due) {
            const title = r.title + tag;
            const result = await sendPushToTokens(tokens, { title, body: r.body, data: { source: 'gst-due', type: r.obligation.type, period: r.obligation.period, due: r.obligation.due, gstin: reg.gstin } });
            await pruneInvalidTokens(result.invalidTokens);
            await Notification.create({ title, body: r.body, targetType: 'role', targetRole: 'admin', source: 'gst-due', data: { type: r.obligation.type, period: r.obligation.period, due: r.obligation.due, gstin: reg.gstin }, successCount: result.successCount, failureCount: result.failureCount });
            await GstReminderLog.insertMany(r.keys.map((k) => ({ key: prefix + k })), { ordered: false }).catch(() => {});
            logger.info(`[GST reminders] "${title}" (${result.successCount} delivered, ${result.failureCount} failed)`);
            total++;
        }
    }
    return total;
}

module.exports = { runGstReminders };
