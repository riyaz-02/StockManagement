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
