const express = require('express');
const router = express.Router();
const { protect, requirePermission } = require('../middleware/auth');
const purchaseBillUpload = require('../middleware/purchaseBillUpload');
const cloudinary = require('../config/cloudinary');
const ctrl = require('../controllers/purchaseController');

// All purchase routes require authentication
router.use(protect);

// ── Bill attachment upload ─────────────────────────────────────────────────────
// POST /api/purchases/upload-bill
// Field name: 'attachment' (single file — image or PDF)
// Returns: { url, publicId, originalName, format }
router.post('/upload-bill', requirePermission('purchases.create'), purchaseBillUpload.single('attachment'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ success: false, message: 'No file uploaded' });
        }

        const isPdf = req.file.mimetype === 'application/pdf';

        res.json({
            success: true,
            data: {
                url: req.file.path,          // Cloudinary secure URL
                publicId: req.file.filename, // public_id for deletion later
                originalName: req.file.originalname,
                format: isPdf ? 'pdf' : (req.file.format || 'image'),
                resourceType: isPdf ? 'raw' : 'image',
            },
        });
    } catch (err) {
        console.error('[Purchase] bill upload error:', err);
        res.status(500).json({ success: false, message: 'File upload failed', error: err.message });
    }
});

// ── Delete a bill attachment from Cloudinary ──────────────────────────────────
// DELETE /api/purchases/attachment/:publicId
router.delete('/attachment/:publicId', requirePermission('purchases.edit'), async (req, res) => {
    try {
        // publicId uses -- for / (same convention as main upload routes)
        const publicId = req.params.publicId.replace(/--/g, '/');
        const result = await cloudinary.uploader.destroy(publicId, { resource_type: 'raw' })
            .catch(() => cloudinary.uploader.destroy(publicId)); // fallback: try image type
        res.json({ success: result.result === 'ok', message: result.result });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Delete failed', error: err.message });
    }
});

// ── ITC Summary for GST filing ────────────────────────────────────────────────
router.get('/itc-summary', requirePermission('purchases.view'), ctrl.getItcSummary);
// ── Autocomplete suggestions from existing records ───────────────────────────
router.get('/suggestions', requirePermission('purchases.view'), ctrl.getPurchaseSuggestions);

// ── Standard CRUD ─────────────────────────────────────────────────────────────
router.get('/preview-gst', requirePermission('purchases.view'), ctrl.previewGst);
router.get('/', requirePermission('purchases.view'), ctrl.getPurchases);
router.get('/:id', requirePermission('purchases.view'), ctrl.getPurchase);
router.post('/', requirePermission('purchases.create'), ctrl.createPurchase);
router.put('/:id', requirePermission('purchases.edit'), ctrl.updatePurchase);
router.delete('/:id', requirePermission('purchases.delete'), ctrl.deletePurchase);

module.exports = router;
