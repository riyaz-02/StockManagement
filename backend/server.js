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

// Initialize express app
const app = express();

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

// Rate limiting
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100, // limit each IP to 100 requests per windowMs
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});

// Apply rate limiting to all API routes
app.use('/api/', limiter);

// Stricter rate limiting for auth routes
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5, // 5 requests per window
  message: 'Too many login attempts, please try again later.',
  skipSuccessfulRequests: true,
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

// Serve static files (uploaded images)
app.use('/api/uploads', express.static(path.join(__dirname, 'uploads')));

// ======================
// DATABASE CONNECTION
// ======================

const mongoOptions = {
  maxPoolSize: 20, // Increased from 10 for better concurrency
  minPoolSize: 5,  // Increased from 2 for faster response
  serverSelectionTimeoutMS: 30000, // Increased to 30 seconds for Railway
  socketTimeoutMS: 45000,
};

// Enable query logging in development
if (process.env.NODE_ENV !== 'production') {
  mongoose.set('debug', true);
}

// Log MongoDB URI (masked) for debugging
const mongoUri = process.env.MONGODB_URI;
if (!mongoUri) {
  logger.error('❌ MONGODB_URI environment variable is not set!');
  process.exit(1);
}
logger.info(`Connecting to MongoDB: ${mongoUri.substring(0, 20)}...`);

mongoose.connect(process.env.MONGODB_URI, mongoOptions)
  .then(() => {
    logger.info('✅ MongoDB connected successfully');
    logger.info(`Database: ${mongoose.connection.name}`);
  })
  .catch((err) => {
    logger.error('❌ MongoDB connection error:', err.message);
    logger.error('Full error:', err);
    process.exit(1);
  });

// MongoDB connection event listeners
mongoose.connection.on('error', (err) => {
  logger.error('MongoDB connection error:', err);
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
  res.status(200).json({
    status: 'ok',
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
app.use('/api/test', require('./routes/test.routes'));

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
process.on('SIGTERM', () => {
  logger.info('SIGTERM received. Shutting down gracefully...');
  server.close(() => {
    logger.info('Process terminated');
    mongoose.connection.close();
  });
});

module.exports = app;
