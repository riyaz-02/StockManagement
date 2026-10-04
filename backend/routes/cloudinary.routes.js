/**
 * /api/upload - upload and delete files (photos, PDFs, videos). Files go to S3 (Cloudinary only while no bucket is set);
 * see services/mediaStore.js. Old Cloudinary links keep working and can still be deleted here.
 */
const express = require('express');
const router = express.Router();
const { mediaUpload, folderFromRequest, MB } = require('../middleware/mediaUpload');
const store = require('../services/mediaStore');
const { protect, requirePermission } = require('../middleware/auth');

const photos = mediaUpload({ allow: ['image'], maxBytes: 12 * MB, folder: folderFromRequest });
const anyFile = mediaUpload({ allow: ['image', 'pdf', 'video'], maxBytes: 150 * MB, folder: folderFromRequest });

const view = (f) => ({ url: f.path, publicId: f.filename, thumbUrl: f.thumbUrl || '', format: f.format, width: f.width, height: f.height, size: f.size, storage: f.storage });

// POST /api/upload/single  (field "image", ?folder=items|containers|users)
router.post('/single', protect, requirePermission('media.upload'), photos.single('image'), (req, res) => {
    if (!req.file) return res.status(400).json({ success: false, message: 'No file uploaded' });
    res.json({ success: true, data: view(req.file) });
});

// POST /api/upload/multiple  (field "images", up to 5)
router.post('/multiple', protect, requirePermission('media.upload'), photos.array('images', 5), (req, res) => {
    if (!req.files || req.files.length === 0) return res.status(400).json({ success: false, message: 'No files uploaded' });
    res.json({ success: true, data: { images: req.files.map(view) } });
});

// POST /api/upload/file  (field "file", ?folder=...): a photo, a PDF or a video (up to 150 MB)
router.post('/file', protect, requirePermission('media.upload'), anyFile.single('file'), (req, res) => {
    if (!req.file) return res.status(400).json({ success: false, message: 'No file uploaded' });
    res.json({ success: true, data: view(req.file) });
});

// POST /api/upload/delete  { url }: delete a file by its link (S3 or Cloudinary)
router.post('/delete', protect, requirePermission('media.upload'), async (req, res) => {
    const url = String((req.body && req.body.url) || '').trim();
    if (!url) return res.status(400).json({ success: false, message: 'Say which file (url)' });
    const ok = await store.removeByUrl(url);
    res.status(ok ? 200 : 404).json({ success: ok, message: ok ? 'Deleted' : 'Not deleted (not one of this shop\'s files, or already gone)' });
});

// DELETE /api/upload/:publicId  (the old way; "/" written as "--"): an S3 key starts with media--, else it is a Cloudinary id
router.delete('/:publicId', protect, requirePermission('media.upload'), async (req, res) => {
    try {
        const id = req.params.publicId.replace(/--/g, '/');
        if (id.startsWith(store.PREFIX)) {
            const ok = await store.removeByUrl(id);
            return res.status(ok ? 200 : 404).json({ success: ok, message: ok ? 'Image deleted successfully' : 'Image not found' });
        }
        const result = await require('../config/cloudinary').uploader.destroy(id);
        if (result.result === 'ok') return res.json({ success: true, message: 'Image deleted successfully' });
        res.status(404).json({ success: false, message: 'Image not found' });
    } catch (error) {
        console.error('Delete error:', error);
        res.status(500).json({ success: false, message: 'Error deleting image' });
    }
});

module.exports = router;
