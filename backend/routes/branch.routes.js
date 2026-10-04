const express = require('express');
const router = express.Router();
const c = require('../controllers/branchController');
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);

// the counters of the branch being worked on (billing screens): every signed-in person
router.get('/counters/current', c.currentCounters);

router.get('/', requirePermission('directory.view'), c.list);
router.post('/', requirePermission('directory.manageBranches'), c.create);
router.get('/:id', requirePermission('directory.manageBranches'), c.get);
router.patch('/:id', requirePermission('directory.manageBranches'), c.update);

router.get('/:id/counters', requirePermission('directory.view'), c.listCounters);
router.post('/:id/counters', requirePermission('directory.manageBranches'), c.createCounter);
router.patch('/:id/counters/:cid', requirePermission('directory.manageBranches'), c.updateCounter);

router.patch('/:id/staff/:userId', requirePermission('users.manage'), c.assignStaff);

module.exports = router;
