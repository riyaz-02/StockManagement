const express = require('express');
const router = express.Router();
const {
    createOutwardMovement,
    returnItem,
    getItemMovements,
    getOutwardMovements,
    getOutwardMovement
} = require('../controllers/outwardMovementController');
const { protect, requirePermission } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

router.post('/', requirePermission('repair.send'), createOutwardMovement);
router.get('/', requirePermission('repair.view'), getOutwardMovements);
router.get('/:id', requirePermission('repair.view'), getOutwardMovement);
router.get('/item/:itemId', requirePermission('repair.view'), getItemMovements);
router.put('/:id/return', requirePermission('repair.return'), returnItem);

module.exports = router;
