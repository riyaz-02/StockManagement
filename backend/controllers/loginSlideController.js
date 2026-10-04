'use strict';
/**
 * The pictures shown on the app sign-in screen (a slideshow above the passcode box).
 *   GET    /api/app-assets/login-slides         public: the active ones, in order (the app shows them before sign-in)
 *   GET    /api/app-assets/login-slides/admin   every one, for the website's Login screen page
 *   POST   /api/app-assets/login-slides         add one (multipart: image + captionEn + captionBn)
 *   PATCH  /api/app-assets/login-slides/:id     captions / on-off
 *   POST   /api/app-assets/login-slides/reorder { ids: [...] } new order
 *   DELETE /api/app-assets/login-slides/:id     remove it (and its file)
 */
const mongoose = require('mongoose');
const AppLoginSlide = require('../models/AppLoginSlide');
const store = require('../services/mediaStore');

const MAX_SLIDES = 8;
const view = (s) => ({ id: String(s._id), imageUrl: s.imageUrl, thumbUrl: s.thumbUrl || '', captionEn: s.captionEn || '', captionBn: s.captionBn || '', active: s.active !== false, order: s.order || 0, width: s.width || 0, height: s.height || 0 });
const caption = (v) => String(v == null ? '' : v).trim().slice(0, 80);
const sorted = () => AppLoginSlide.find({}).sort({ order: 1, createdAt: 1 }).lean();
const truthy = (v) => v === true || v === 'true' || v === 1 || v === '1' || v === 'on';

exports.publicList = async (req, res) => {
    try {
        const rows = (await sorted()).filter((s) => s.active !== false);
        res.set('Cache-Control', 'public, max-age=120');
        res.json({ success: true, data: { slides: rows.map(view), version: rows.map((s) => `${s._id}:${new Date(s.updatedAt || 0).getTime()}`).join('|') } });
    } catch (e) { res.status(500).json({ success: false, message: 'Could not load the pictures' }); }
};

exports.adminList = async (req, res) => {
    try { res.json({ success: true, data: { slides: (await sorted()).map(view), max: MAX_SLIDES } }); }
    catch (e) { res.status(500).json({ success: false, message: 'Could not load the pictures' }); }
};

exports.create = async (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ success: false, message: 'Choose a picture' });
        const f = req.file;
        if (await AppLoginSlide.countDocuments({}) >= MAX_SLIDES) {
            await store.removeByUrl(f.path).catch(() => {});
            return res.status(400).json({ success: false, message: `At most ${MAX_SLIDES} pictures: remove one first` });
        }
        const last = await AppLoginSlide.findOne({}).sort({ order: -1 }).select('order').lean();
        const doc = await AppLoginSlide.create({
            imageUrl: f.path, thumbUrl: f.thumbUrl || '', publicId: f.filename || '', width: f.width, height: f.height,
            captionEn: caption(req.body.captionEn), captionBn: caption(req.body.captionBn),
            order: ((last && last.order) || 0) + 1, active: true, createdByName: (req.user && req.user.name) || '',
        });
        res.status(201).json({ success: true, data: view(doc) });
    } catch (e) { console.error('[login-slides] create:', e.message); res.status(500).json({ success: false, message: 'Could not save the picture' }); }
};

exports.update = async (req, res) => {
    try {
        if (!mongoose.isValidObjectId(req.params.id)) return res.status(404).json({ success: false, message: 'Not found' });
        const set = {};
        if (req.body.captionEn !== undefined) set.captionEn = caption(req.body.captionEn);
        if (req.body.captionBn !== undefined) set.captionBn = caption(req.body.captionBn);
        if (req.body.active !== undefined) set.active = truthy(req.body.active);
        const doc = await AppLoginSlide.findByIdAndUpdate(req.params.id, { $set: set }, { new: true }).lean();
        if (!doc) return res.status(404).json({ success: false, message: 'Not found' });
        res.json({ success: true, data: view(doc) });
    } catch (e) { res.status(500).json({ success: false, message: 'Could not save' }); }
};

exports.reorder = async (req, res) => {
    try {
        const ids = Array.isArray(req.body.ids) ? req.body.ids.map(String).filter((i) => mongoose.isValidObjectId(i)) : [];
        if (!ids.length) return res.status(400).json({ success: false, message: 'Send the new order (ids)' });
        const all = (await sorted()).map((s) => String(s._id));
        // the ids sent go first, in that order; any not mentioned keep their relative order after them
        const next = [...ids.filter((i) => all.includes(i)), ...all.filter((i) => !ids.includes(i))];
        await Promise.all(next.map((id, i) => AppLoginSlide.updateOne({ _id: id }, { $set: { order: i + 1 } })));
        res.json({ success: true, data: { slides: (await sorted()).map(view) } });
    } catch (e) { res.status(500).json({ success: false, message: 'Could not reorder' }); }
};

exports.remove = async (req, res) => {
    try {
        if (!mongoose.isValidObjectId(req.params.id)) return res.status(404).json({ success: false, message: 'Not found' });
        const doc = await AppLoginSlide.findByIdAndDelete(req.params.id).lean();
        if (!doc) return res.status(404).json({ success: false, message: 'Not found' });
        await store.removeByUrl(doc.imageUrl).catch(() => {});
        res.json({ success: true, message: 'Removed' });
    } catch (e) { res.status(500).json({ success: false, message: 'Could not remove' }); }
};
