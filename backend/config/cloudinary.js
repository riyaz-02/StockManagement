const cloudinary = require('cloudinary').v2;

// Check if Cloudinary credentials are provided
if (process.env.CLOUDINARY_CLOUD_NAME &&
    process.env.CLOUDINARY_API_KEY &&
    process.env.CLOUDINARY_API_SECRET) {

    cloudinary.config({
        cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
        api_key: process.env.CLOUDINARY_API_KEY,
        api_secret: process.env.CLOUDINARY_API_SECRET
    });

    console.log('✅ Cloudinary configured successfully');
} else {
    console.warn('⚠️  Cloudinary credentials not provided - image uploads will not work');
    console.warn('   Set CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, and CLOUDINARY_API_SECRET');
}

module.exports = cloudinary;
