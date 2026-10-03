const mongoose = require('mongoose');

// The shared "what changed" log. Every important change (rate, settings, permissions, notification, app update, data in a
// module) becomes one event with a rising number (seq). The app and the website listen live (services/events.js); a client
// that was away asks "everything after #N" and applies what it missed. Events expire after 7 days.
const schema = new mongoose.Schema(
    {
        seq: { type: Number, required: true, unique: true },
        type: { type: String, required: true },              // rate.changed, settings.changed, permissions.changed, app.update, notification.new, data.changed
        module: { type: String, default: '' },               // for data.changed: billing, stock, orders...
        branchId: { type: String, default: 'all' },          // 'all' or one branch
        audience: {                                          // who may see it; both empty = everyone allowed by the branch
            roles: { type: [String], default: [] },
            userIds: { type: [String], default: [] },
        },
        data: { type: mongoose.Schema.Types.Mixed, default: {} },
        actorId: { type: String, default: '' },
        actorName: { type: String, default: '' },
        at: { type: Date, default: Date.now },
    },
    { collection: 'app_events', versionKey: false }
);
schema.index({ at: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 7 });
module.exports = mongoose.models.AppEvent || mongoose.model('AppEvent', schema);
