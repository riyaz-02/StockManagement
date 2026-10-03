const express = require('express');
const router = express.Router();
const c = require('../controllers/liveController');
const { protect } = require('../middleware/auth');
const Events = require('../services/events');

// The stream can be opened with a normal login (the app) or with a one-time ticket (a browser).
const streamAuth = (req, res, next) => {
    if (req.query.ticket) {
        const viewer = Events.consumeTicket(req.query.ticket);
        if (!viewer) return res.status(401).json({ success: false, message: 'This live link has expired. Reload the page.' });
        req.viewer = viewer;
        return next();
    }
    return protect(req, res, next);
};

router.get('/', streamAuth, c.stream);
router.post('/ticket', protect, c.ticket);
router.get('/events', protect, c.events);

module.exports = router;
