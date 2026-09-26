/**
 * directory.routes.js — User Directory (customers / staff / suppliers / karigars)
 *
 * The backing DB is production and shared with the legacy web admin, so:
 *   - there is NO delete anywhere;
 *   - edits (PUT) are whitelisted, permission-gated, audited and
 *     conflict-checked (see controllers/directoryController.js).
 */
const express = require('express');
const router = express.Router();
const { protect, requirePermission } = require('../middleware/auth');
const rateLimit = require('express-rate-limit');
const ctrl = require('../controllers/directoryController');

// The auto-fill endpoints call third-party services: cap them per signed-in user.
const autofillLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 150,
    standardHeaders: true,
    legacyHeaders: false,
    keyGenerator: (req) => String((req.user && req.user._id) || 'anon'),
    message: { success: false, message: 'Too many auto-fill requests, slow down a little.' },
});

router.use(protect);

router.get('/summary', requirePermission('directory.view'), ctrl.summary);

// Auto-fill helpers (Bengali, pincode, IFSC)
router.post('/translate', requirePermission('directory.view'), autofillLimiter, ctrl.translate);
router.get('/lookup/pincode/:pin', requirePermission('directory.view'), autofillLimiter, ctrl.lookupPincode);
router.get('/lookup/ifsc/:code', requirePermission('directory.view'), autofillLimiter, ctrl.lookupIfsc);

// Edit history (who changed what)
router.get('/history/:entity/:id', requirePermission('directory.edit'), ctrl.history);

router.get('/branches', requirePermission('directory.view'), ctrl.listBranches);
router.post('/branches', requirePermission('directory.manageBranches'), ctrl.createBranch);

router.get('/customers', requirePermission('directory.view'), ctrl.listCustomers);
// NOTE: must be registered before '/customers/:id' or 'lookup' would be read as an id.
router.get('/customers/lookup', requirePermission('directory.view'), ctrl.lookupCustomers);
router.get('/customers/:id', requirePermission('directory.view'), ctrl.getCustomer);
router.post('/customers', requirePermission('directory.create'), ctrl.createCustomer);
router.put('/customers/:id', requirePermission('directory.edit'), ctrl.updateCustomer);

router.get('/suppliers', requirePermission('directory.view'), ctrl.listSuppliers);
router.get('/suppliers/:id', requirePermission('directory.view'), ctrl.getSupplier);
router.post('/suppliers', requirePermission('directory.create'), ctrl.createSupplier);
router.put('/suppliers/:id', requirePermission('directory.edit'), ctrl.updateSupplier);

router.get('/karigars', requirePermission('directory.view'), ctrl.listKarigars);
router.get('/karigars/:id', requirePermission('directory.view'), ctrl.getKarigar);
router.post('/karigars', requirePermission('directory.create'), ctrl.createKarigar);
router.put('/karigars/:id', requirePermission('directory.edit'), ctrl.updateKarigar);

router.get('/staff', requirePermission('directory.viewStaff'), ctrl.listStaff);
router.get('/staff/:source/:id', requirePermission('directory.viewStaff'), ctrl.getStaff);
router.post('/staff', requirePermission('directory.createStaff'), ctrl.createStaff);
// HR profiles only. Legacy web-admin login accounts (password hashes) are NOT editable here.
router.put('/staff/profile/:id', requirePermission('directory.editStaff'), ctrl.updateStaff);

module.exports = router;
