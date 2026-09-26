const express = require('express');
const router = express.Router();
const c = require('../controllers/expenseController');
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);
router.get('/', requirePermission('expenses.view'), c.list);
router.post('/', requirePermission('expenses.create'), c.create);
router.delete('/:id', requirePermission('expenses.delete'), c.cancel);

module.exports = router;
