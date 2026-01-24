const fs = require('fs');
const path = require('path');

/**
 * Environment Configuration Checker
 * Validates that all required environment variables are set
 */

const requiredEnvVars = [
    'NODE_ENV',
    'PORT',
    'MONGODB_URI',
    'JWT_SECRET',
    'JWT_EXPIRE',
    'CLOUDINARY_CLOUD_NAME',
    'CLOUDINARY_API_KEY',
    'CLOUDINARY_API_SECRET',
    'CORS_ORIGIN'
];

const productionOnlyVars = [
    'SENTRY_DSN' // Optional but recommended for production
];

console.log('🔍 Checking environment configuration...\n');

let hasErrors = false;
let hasWarnings = false;

// Check required variables
requiredEnvVars.forEach(varName => {
    if (!process.env[varName]) {
        console.error(`❌ Missing required environment variable: ${varName}`);
        hasErrors = true;
    } else {
        console.log(`✅ ${varName}: Set`);
    }
});

// Check JWT secret strength
if (process.env.JWT_SECRET) {
    if (process.env.JWT_SECRET.length < 32) {
        console.warn(`⚠️  JWT_SECRET is too short (${process.env.JWT_SECRET.length} chars). Recommended: 64+ characters`);
        hasWarnings = true;
    }
    if (process.env.JWT_SECRET.includes('change') || process.env.JWT_SECRET.includes('secret')) {
        console.error('❌ JWT_SECRET appears to be a default value. Generate a strong secret!');
        hasErrors = true;
    }
}

// Check CORS in production
if (process.env.NODE_ENV === 'production' && process.env.CORS_ORIGIN === '*') {
    console.error('❌ CORS_ORIGIN is set to * in production. This is a security risk!');
    hasErrors = true;
}

// Production-specific checks
if (process.env.NODE_ENV === 'production') {
    console.log('\n📦 Production environment detected. Running additional checks...\n');

    productionOnlyVars.forEach(varName => {
        if (!process.env[varName]) {
            console.warn(`⚠️  Recommended for production: ${varName}`);
            hasWarnings = true;
        }
    });
}

// Summary
console.log('\n' + '='.repeat(50));
if (hasErrors) {
    console.error('❌ Environment check FAILED. Fix the errors above before deploying.');
    process.exit(1);
} else if (hasWarnings) {
    console.warn('⚠️  Environment check passed with warnings. Review the warnings above.');
    process.exit(0);
} else {
    console.log('✅ Environment check PASSED. All required variables are set.');
    process.exit(0);
}
