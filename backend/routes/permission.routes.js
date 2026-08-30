const express = require('express');
const router = express.Router();
const {
    getDefinitions,
    getMyPermissions,
    getRoleGrids,
    updateRoleGrid
} = require('../controllers/permissionController');
const { protect, authorize } = require('../middleware/auth');

router.use(protect);

// Any authenticated user
router.get('/definitions', getDefinitions);
router.get('/me', getMyPermissions);

// Admin/owner only — this endpoint IS the permission-manager data, so it
// stays on the plain role check rather than a permission key.
router.get('/roles', authorize('admin', 'owner'), getRoleGrids);
router.put('/roles/:role', authorize('admin', 'owner'), updateRoleGrid);

module.exports = router;
