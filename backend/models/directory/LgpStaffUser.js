/**
 * LgpStaffUser.js — the EXISTING production `users` collection on the LGP
 * admin cluster: the legacy web-admin login accounts.
 *
 * READ-ONLY. It holds password hashes and remember-me tokens, so the
 * controller only ever selects the explicit whitelist in SAFE_FIELDS. Do not
 * add create/update/delete code for this model.
 */
const mongoose = require('mongoose');

const SAFE_FIELDS =
    'username email full_name role contact address profile_image is_active status last_login created_at';

const schema = new mongoose.Schema(
    {
        username: String,
        email: String,
        full_name: String,
        role: String,
        contact: String,
        address: String,
        profile_image: String,
        is_active: Boolean,
        status: String,
        last_login: Date,
        created_at: Date,
    },
    { collection: 'users', versionKey: false, autoIndex: false, autoCreate: false }
);

module.exports = (conn) => conn.models.LgpStaffUser || conn.model('LgpStaffUser', schema);
module.exports.SAFE_FIELDS = SAFE_FIELDS;
