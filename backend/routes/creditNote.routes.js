const express = require('express');
const router = express.Router();
const c = require('../controllers/creditNoteController');
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);
router.get('/', requirePermission('billing.view'), c.list);
router.get('/invoice/:id', requirePermission('billing.view'), c.forInvoice);
router.post('/preview', requirePermission('billing.creditNote'), c.preview);
router.post('/', requirePermission('billing.creditNote'), c.create);
router.get('/:id', requirePermission('billing.view'), c.get);

module.exports = router;
