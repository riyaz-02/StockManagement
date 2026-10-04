const mongoose = require('mongoose');

// One picture of the sign-in screen slideshow (app). Uploaded on the website (Admin Control > Login screen), shown by
// the app before anyone is signed in (public read: GET /api/app-assets/login-slides). `order` = position (1 first).
const schema = new mongoose.Schema(
    {
        imageUrl: { type: String, required: true },
        thumbUrl: { type: String, default: '' },
        publicId: { type: String, default: '' },
        width: Number,
        height: Number,
        captionEn: { type: String, default: '', trim: true, maxlength: 80 },
        captionBn: { type: String, default: '', trim: true, maxlength: 80 },
        order: { type: Number, default: 0 },
        active: { type: Boolean, default: true },
        createdByName: { type: String, default: '' },
    },
    { collection: 'app_login_slides', timestamps: true, versionKey: false }
);
schema.index({ order: 1, createdAt: 1 });
module.exports = mongoose.models.AppLoginSlide || mongoose.model('AppLoginSlide', schema);
