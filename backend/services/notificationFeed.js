/**
 * notificationFeed.js - what the bell shows, for the phone app and the website.
 *
 *   notices   = every push notification the server sent (manual sends, GST due reminders, app updates ...) that this person
 *               was meant to get, newest first (the `notifications` collection is the log).
 *   reminders = things that are true RIGHT NOW and need someone to act, worked out when the bell is opened:
 *               today's rate not set, a GST return due soon or overdue, the stock has not been tallied for a month.
 *               They disappear by themselves once the job is done, so they are never "read" or stale.
 *
 * Unread = notices newer than the last time this person opened the bell, plus the reminders (they are still open jobs).
 * "Seen" is kept per person in `app_notification_reads` (the website's `users` collection is left alone).
 */
'use strict';
const mongoose = require('mongoose');
const Notification = require('../models/Notification');
const { hasPermission } = require('../middleware/auth');

const DAY = 24 * 60 * 60 * 1000;
const FULL = ['admin', 'owner'];
const reads = () => mongoose.connection.collection('app_notification_reads');

const when = (d) => (d instanceof Date ? d : new Date(d));

/** Notices this person was meant to get (everyone, their role, or - for admin / owner - everything). */
function notice(n) {
    return {
        id: `n:${n._id}`, kind: 'notice', level: n.source === 'app-update' ? 'update' : 'info',
        title: n.title, body: n.body, at: when(n.createdAt).toISOString(), source: n.source || 'manual', link: noticeLink(n),
    };
}

/** Where tapping a notice goes (the app and the website both understand these names). */
function noticeLink(n) {
    const s = String(n.source || '');
    if (s === 'gst-due' || s === 'gst-reminder') return 'gst';
    if (s === 'weekly-stock-check') return 'tally';
    if (s === 'app-update') return 'update';
    return '';
}

async function liveReminders(user, lang = 'en') {
    const bn = lang === 'bn';
    const out = [];
    const Calc = require('./billingCalc');
    const today = Calc.todayIST();

    // today's rate: bills, old metal and stock forms all start from it
    try {
        if (await hasPermission(user, 'rates.edit')) {
            const Rate = require('../models/AppRate');
            const d = await Rate.findOne({ key: 'main' }).lean();
            const set = !!(d && d.updatedAt && Calc.todayIST(new Date(d.updatedAt)) === today);
            if (!set) out.push({ id: 'r:rate', kind: 'reminder', level: d && (d.gold > 0 || d.silver > 0) ? 'warn' : 'bad', title: bn ? 'আজকের সোনা ও রূপার দাম দিন' : 'Set today\'s gold and silver rate', body: bn ? 'নতুন বিল ও ফর্ম এই দাম থেকে শুরু হয়।' : 'New bills and forms start from the rate.', at: null, link: 'rate' });
        }
    } catch (_) { /* a reminder that cannot be worked out is simply not shown */ }

    // GST returns: overdue or due within the reminder lead time, per registration (GSTIN)
    try {
        if (await hasPermission(user, 'gst.viewReports')) {
            const G = require('./gstReports');
            const Filings = require('./gstFilings');
            const { _loadSettings, _filingKey } = require('../controllers/gstReportsController');
            const { loadRegistrations } = require('./registrations');
            const regs = await loadRegistrations();
            for (const reg of regs) {
                const { settings } = await _loadSettings(reg);
                if (settings.reminders && settings.reminders.enabled === false) continue;
                const filings = await Filings.list({ gstin: _filingKey(reg) });
                for (const a of G.alerts(settings, filings, today).slice(0, 4)) {
                    const tag = regs.length > 1 ? ` (${reg.gstin})` : '';
                    const text = bn
                        ? (a.daysLeft < 0 ? `-এর শেষ তারিখ ${a.due} পেরিয়ে গেছে (${-a.daysLeft} দিন)` : a.daysLeft === 0 ? ' আজই জমা দিতে হবে' : a.daysLeft === 1 ? ' কাল জমা দিতে হবে' : ` ${a.daysLeft} দিনের মধ্যে (${a.due}) জমা দিতে হবে`)
                        : (a.daysLeft < 0 ? ` was due on ${a.due} (${-a.daysLeft} day${a.daysLeft === -1 ? '' : 's'} ago)` : a.daysLeft === 0 ? ' is due TODAY' : a.daysLeft === 1 ? ' is due tomorrow' : ` is due in ${a.daysLeft} days (${a.due})`);
                    out.push({ id: `r:gst:${reg.gstin}:${a.type}:${a.period}`, kind: 'reminder', level: a.daysLeft < 0 ? 'bad' : a.daysLeft <= 3 ? 'warn' : 'info', title: `${a.type}${text}`.slice(0, 120), body: bn ? `${a.periodLabel}${tag}। জমা হলে GST-তে "filed" চিহ্ন দিন।` : `${a.periodLabel}${tag}. Mark it as filed in GST once done.`, at: null, link: 'gst' });
                }
            }
        }
    } catch (_) { /* skip */ }

    // stock tally: a month without one means differences go unnoticed
    try {
        if (await hasPermission(user, 'tally.view')) {
            const T = require('../models/TallySession');
            const last = await T.findOne({ status: { $in: ['locked', 'force_locked'] } }).sort({ lockedAt: -1, createdAt: -1 }).select('lockedAt createdAt').lean();
            const at = last ? when(last.lockedAt || last.createdAt).getTime() : 0;
            const days = at ? Math.floor((Date.now() - at) / DAY) : null;
            if (days === null || days >= 30) out.push({ id: 'r:tally', kind: 'reminder', level: 'warn', title: bn ? (days === null ? 'স্টক এখনও ট্যালি করা হয়নি' : `শেষ স্টক ট্যালি ${days} দিন আগে`) : (days === null ? 'The stock has never been tallied' : `The last stock tally was ${days} days ago`), body: bn ? 'দোকান গুনে স্টকের সাথে মেলান।' : 'Count the shop and match it with the stock.', at: null, link: 'tally' });
        }
    } catch (_) { /* skip */ }
    return out;
}

async function feedFor(user, { limit = 40, lang = 'en' } = {}) {
    const uid = String(user._id || user.id);
    const role = String(user.role || '').toLowerCase();
    const since = new Date(Date.now() - 30 * DAY);
    const q = { createdAt: { $gte: since } };
    if (!FULL.includes(role)) q.$or = [{ targetType: 'all' }, { targetType: 'role', targetRole: new RegExp(`^${role.replace(/[^a-z0-9_]/g, '')}$`, 'i') }];
    const [rows, rd, reminders] = await Promise.all([
        Notification.find(q).sort({ createdAt: -1 }).limit(Math.min(Math.max(limit, 1), 100)).lean(),
        reads().findOne({ _id: uid }),
        liveReminders(user, lang),
    ]);
    const seenAt = rd && rd.seenAt ? new Date(rd.seenAt).getTime() : 0;
    const notices = rows.map((n) => ({ ...notice(n), read: when(n.createdAt).getTime() <= seenAt }));
    return { items: [...reminders, ...notices], unread: reminders.length + notices.filter((x) => !x.read).length, reminders: reminders.length, seenAt: seenAt ? new Date(seenAt).toISOString() : null };
}

async function markSeen(user) {
    const uid = String(user._id || user.id);
    await reads().updateOne({ _id: uid }, { $set: { seenAt: new Date() } }, { upsert: true });
}

module.exports = { feedFor, markSeen, liveReminders };
