const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const morgan = require('morgan');
const dotenv = require('dotenv');
const path = require('path');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const mongoSanitize = require('express-mongo-sanitize');
const hpp = require('hpp');
const compression = require('compression');
const logger = require('./config/logger');
const { createIdleShutdown } = require('./config/idleShutdown');

// Load environment variables
dotenv.config();

// Import routes
const authRoutes = require('./routes/auth.routes');
const containerRoutes = require('./routes/container.routes');
const itemRoutes = require('./routes/item.routes');
const scanRoutes = require('./routes/scan.routes');
const repairRoutes = require('./routes/repair.routes');
const tallyRoutes = require('./routes/tally.routes');
const reportRoutes = require('./routes/report.routes');
const bookingRoutes = require('./routes/booking.routes');
const settingsRoutes = require('./routes/settings');
const customerRoutes = require('./routes/customer.routes');
const tagPrintRoutes = require('./routes/tagPrint.routes');
const analyticsRoutes = require('./routes/analytics.routes');
const cloudinaryRoutes = require('./routes/cloudinary.routes');
// Store management routes (shopmanage DB)
const purchaseRoutes = require('./routes/purchase.routes');
const stockRoutes    = require('./routes/stock.routes');
const gstRoutes      = require('./routes/gst.routes');

// Initialize express app
const app = express();
const idleShutdown = createIdleShutdown();

// ======================
// PROXY CONFIGURATION
// ======================

// Trust proxy - Required for Railway and other cloud platforms
// This allows express-rate-limit to correctly identify client IPs
app.set('trust proxy', 1);

// ======================
// SECURITY MIDDLEWARE
// ======================

// Set security HTTP headers
app.use(helmet({
  contentSecurityPolicy: false, // Disable for API
  crossOriginEmbedderPolicy: false
}));

// Data sanitization against NoSQL query injection
app.use(mongoSanitize());

// Prevent parameter pollution
app.use(hpp());

// Rate limiting - Skip for authenticated users
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 1000, // Increased to 1000 for stock audit/tally operations
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
  // Skip rate limiting for authenticated users (they have a valid JWT token)
  skip: (req) => {
    const authHeader = req.headers.authorization;
    return authHeader && authHeader.startsWith('Bearer ');
  }
});

// Apply rate limiting to all API routes (but skips authenticated users)
app.use('/api/', limiter);

// Stricter rate limiting for auth routes (login/register)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.AUTH_LIMIT_MAX, 10) || 10, // failed logins per address per 15 minutes (AUTH_LIMIT_MAX raises it for local test runs)
  message: 'Too many login attempts, please try again later.',
  skipSuccessfulRequests: true,
  // the website logs everyone in from one address: it passes the visitor's address with a shared secret (see utils/clientIp.js)
  keyGenerator: (req) => require('./utils/clientIp').trustedClientIp(req),
});

// ======================
// GENERAL MIDDLEWARE
// ======================

// CORS - Allow localhost for development
const corsOptions = {
  origin: function (origin, callback) {
    // Allow requests with no origin (like mobile apps or curl requests)
    if (!origin) return callback(null, true);

    const allowedOrigins = [
      process.env.CORS_ORIGIN,
      'http://localhost:3000',
      'http://localhost:8080',
      /^http:\/\/localhost:\d+$/,  // Any localhost port
      /^http:\/\/127\.0\.0\.1:\d+$/  // Any 127.0.0.1 port
    ];

    // Check if origin matches any allowed pattern
    const isAllowed = allowedOrigins.some(allowed => {
      if (typeof allowed === 'string') {
        return origin === allowed;
      } else if (allowed instanceof RegExp) {
        return allowed.test(origin);
      }
      return false;
    });

    if (isAllowed || process.env.CORS_ORIGIN === '*') {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true
};

app.use(cors(corsOptions));

// Response compression - reduces payload size by 60-80%
app.use(compression({
  filter: (req, res) => {
    if (req.headers['x-no-compression']) {
      return false;
    }
    // the live stream must not be buffered by compression
    if (req.path.startsWith('/api/live') && !req.path.startsWith('/api/live/events') && !req.path.startsWith('/api/live/ticket')) {
      return false;
    }
    return compression.filter(req, res);
  },
  level: 6 // Balance between compression ratio and speed
}));

// Body parser with size limits
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Logging
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev', {
  stream: logger.stream
}));

// Optional EC2 cost saver: stop the server after a short idle window in production.
app.use(idleShutdown.middleware);

// Serve static files (uploaded images)
app.use('/api/uploads', express.static(path.join(__dirname, 'uploads')));

// ======================
// DATABASE CONNECTION
// ======================

// Enable query logging in development
if (process.env.NODE_ENV !== 'production') {
  mongoose.set('debug', true);
}

// ONE database, ONE connection (see config/db.js)
const { connectPrimary } = require('./config/db');

// The server answers /health as soon as it listens, but says "starting" (503) until every database is connected, so the
// app never opens onto a server that cannot yet log anyone in. A database that is slow at boot (the machine has just
// started) is retried a few times before giving up, instead of killing the process on the first hiccup.
let dbReady = false;
const withRetry = async (name, fn, tries = 4) => {
  for (let i = 1; ; i++) {
    try {
      return await fn();
    } catch (err) {
      if (i >= tries) throw err;
      logger.warn(`[DB] ${name} not ready (attempt ${i}/${tries}): ${err.message}. Retrying...`);
      await new Promise((r) => setTimeout(r, 1500 * i));
    }
  }
};

withRetry('database', connectPrimary)
  .then(() => {
    dbReady = true;
    logger.info(`✅ Database connected (${process.uptime().toFixed(1)}s after start)`);
    require('./config/scheduledNotifications').startScheduledNotifications();
  })
  .catch((err) => {
    logger.error('❌ Database connection error:', err.message);
    process.exit(1);
  });

// Connection event listeners
mongoose.connection.on('error', (err) => {
  logger.error('MongoDB error:', err);
});

mongoose.connection.on('disconnected', () => {
  logger.warn('MongoDB disconnected');
});

mongoose.connection.on('reconnected', () => {
  logger.info('MongoDB reconnected');
});

// Initialize Cloudinary
require('./config/cloudinary');

// ======================
// HEALTH CHECK
// ======================
app.get('/health', (req, res) => {
  res.status(dbReady ? 200 : 503).json({
    status: dbReady ? 'ok' : 'starting',
    ready: dbReady,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'development'
  });
});

// ======================
// API ROUTES
// ======================

// Auth routes with stricter rate limiting
app.use('/api/auth', authLimiter, authRoutes);

// Other routes
app.use('/api/users', require('./routes/user.routes'));
app.use('/api/containers', containerRoutes);
app.use('/api/items', itemRoutes);
app.use('/api/scan', scanRoutes);
app.use('/api/repair', repairRoutes);
app.use('/api/tally', tallyRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/bookings', require('./routes/booking.routes'));
app.use('/api/settings', require('./routes/settings'));
app.use('/api/customers', require('./routes/customer.routes'));
app.use('/api/outward-movements', require('./routes/outwardMovement.routes'));
app.use('/api/tag-settings', require('./routes/tagSettings.routes'));
app.use('/api/tag-print', require('./routes/tagPrint.routes'));
app.use('/api/analytics', analyticsRoutes);
app.use('/api/upload', cloudinaryRoutes);
app.use('/api/inventory-snapshots', require('./routes/inventory.routes'));
app.use('/api/app-version', require('./routes/appVersion.routes'));
app.use('/api/notifications', require('./routes/notification.routes'));
app.use('/api/permissions', require('./routes/permission.routes'));
app.use('/api/test', require('./routes/test.routes'));
// Store management (shopmanage DB)
app.use('/api/purchases', purchaseRoutes);
app.use('/api/stock',     stockRoutes);
app.use('/api/gst',       gstRoutes);
app.use('/api/directory', require('./routes/directory.routes'));
app.use('/api/billing', require('./routes/billing.routes'));
app.use('/api/gst-reports', require('./routes/gstReports.routes'));
app.use('/api/stock-settings', require('./routes/stockSettings.routes'));
app.use('/api/old-metal', require('./routes/oldMetal.routes'));
app.use('/api/credit-notes', require('./routes/creditNote.routes'));
app.use('/api/rates', require('./routes/rate.routes'));
app.use('/api/estimates', require('./routes/estimate.routes'));
app.use('/api/orders', require('./routes/order.routes'));
app.use('/api/live', require('./routes/live.routes'));
app.use('/api/presence', require('./routes/presence.routes'));
app.use('/api/expenses', require('./routes/expense.routes'));
app.use('/api/admin', require('./routes/admin.routes'));
// Static admin dashboard (its own login; every data call is JWT + admin-role protected)
app.use('/admin', express.static(path.join(__dirname, 'public', 'admin')));

// ======================
// ERROR HANDLING
// ======================

const { errorHandler, notFound } = require('./middleware/errorHandler');

// 404 handler (must be after all routes)
app.use(notFound);

// Global error handler (must be last)
app.use(errorHandler);

// ======================
// SERVER STARTUP
// ======================

const PORT = process.env.PORT || 5000;

const server = app.listen(PORT, () => {
  logger.info(`🚀 Server running in ${process.env.NODE_ENV || 'development'} mode on port ${PORT}`);
  idleShutdown.start();
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (err) => {
  logger.error('Unhandled Rejection:', err);
  server.close(() => process.exit(1));
});

// Handle uncaught exceptions
process.on('uncaughtException', (err) => {
  logger.error('Uncaught Exception:', err);
  process.exit(1);
});

// Graceful shutdown
const { closeAll } = require('./config/db');
process.on('SIGTERM', () => {
  logger.info('SIGTERM received. Shutting down gracefully...');
  server.close(async () => {
    await closeAll();
    logger.info('Process terminated');
  });
});

module.exports = app;
