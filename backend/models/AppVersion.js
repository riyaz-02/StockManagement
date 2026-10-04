/**
 * AppVersion.js — single config doc controlling the "update available" nudge
 * shown to users on app launch (splash screen). Admin-editable via
 * PUT /api/app-version.
 */

const mongoose = require('mongoose');

const appVersionSchema = new mongoose.Schema(
    {
        latestVersion: {
            type: String,
            required: true,
            trim: true,
            default: '1.0.0',
        },
        // Matches the Flutter build number (pubspec.yaml "x.y.z+N" -> N)
        latestVersionCode: {
            type: Number,
            required: true,
            default: 1,
        },
        // If true, any app below latestVersionCode must update before continuing
        forceUpdate: {
            type: Boolean,
            default: false,
        },
        downloadUrl: {
            type: String,
            trim: true,
            default: 'https://lgp.skriyaz.com/app',
        },
        updateMessage: {
            type: String,
            trim: true,
            default: 'A new version of the app is available.',
        },
        // The published APK that phones download (uploaded on the website: Admin > App updates). `file` is a name inside
        // uploads/app/, never a path from outside. When there is none, `downloadUrl` is used as typed (an outside link).
        apk: {
            file: { type: String, default: '' },
            versionName: { type: String, default: '' },
            versionCode: { type: Number, default: 0 },
            sizeBytes: { type: Number, default: 0 },
            sha256: { type: String, default: '' },
            publishedAt: { type: Date, default: null },
        },
        // An uploaded APK that is checked and waiting to be published (so a wrong file never reaches the phones).
        staged: {
            file: { type: String, default: '' },
            versionName: { type: String, default: '' },
            versionCode: { type: Number, default: 0 },
            sizeBytes: { type: Number, default: 0 },
            sha256: { type: String, default: '' },
            uploadedAt: { type: Date, default: null },
            uploadedByName: { type: String, default: '' },
        },
        // What was published, newest last (for the history table).
        releases: { type: [Object], default: [] },
        // A temporary "come back later" gate on sign-in only (app + website share /api/auth/login). Admin/owner can
        // always still sign in, so whoever turned it on can turn it back off.
        maintenanceMode: {
            enabled: { type: Boolean, default: false },
            message: { type: String, trim: true, default: 'The shop app is briefly unavailable. Please try again shortly.' },
        },
        updatedBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
        },
        isActive: {
            type: Boolean,
            default: true,
        },
    },
    { timestamps: true }
);

module.exports = mongoose.model('AppVersion', appVersionSchema);
