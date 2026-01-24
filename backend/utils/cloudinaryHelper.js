const cloudinary = require('../config/cloudinary');

/**
 * Delete image from Cloudinary
 * @param {string} imageUrl - Full Cloudinary URL
 * @returns {Promise<boolean>} - Success status
 */
const deleteCloudinaryImage = async (imageUrl) => {
    try {
        // Extract public_id from Cloudinary URL
        // URL format: https://res.cloudinary.com/cloud-name/image/upload/v1234567/folder/filename.jpg
        const urlParts = imageUrl.split('/');
        const uploadIndex = urlParts.indexOf('upload');

        if (uploadIndex === -1) {
            console.log('Not a Cloudinary URL, skipping deletion');
            return false;
        }

        // Get everything after 'upload/v123456/'
        const publicIdWithExt = urlParts.slice(uploadIndex + 2).join('/');
        // Remove file extension
        const publicId = publicIdWithExt.substring(0, publicIdWithExt.lastIndexOf('.'));

        const result = await cloudinary.uploader.destroy(publicId);

        if (result.result === 'ok' || result.result === 'not found') {
            console.log(`✅ Deleted image: ${publicId}`);
            return true;
        } else {
            console.log(`⚠️ Failed to delete image: ${publicId}`, result);
            return false;
        }
    } catch (error) {
        console.error('Error deleting Cloudinary image:', error);
        return false;
    }
};

/**
 * Delete multiple images from Cloudinary
 * @param {string[]} imageUrls - Array of Cloudinary URLs
 * @returns {Promise<number>} - Number of successfully deleted images
 */
const deleteCloudinaryImages = async (imageUrls) => {
    if (!imageUrls || imageUrls.length === 0) return 0;

    const deletePromises = imageUrls.map(url => deleteCloudinaryImage(url));
    const results = await Promise.all(deletePromises);

    const successCount = results.filter(r => r === true).length;
    console.log(`✅ Deleted ${successCount}/${imageUrls.length} images from Cloudinary`);

    return successCount;
};

/**
 * Generate optimized image URL
 * @param {string} imageUrl - Original Cloudinary URL
 * @param {object} options - Transformation options
 * @returns {string} - Optimized URL
 */
const getOptimizedImageUrl = (imageUrl, options = {}) => {
    const {
        width = 400,
        height = 400,
        crop = 'limit',
        quality = 'auto:good',
        format = 'auto'
    } = options;

    if (!imageUrl || !imageUrl.includes('cloudinary.com')) {
        return imageUrl; // Return original if not Cloudinary URL
    }

    // Build transformation string
    const transformations = `w_${width},h_${height},c_${crop},q_${quality},f_${format}`;

    // Insert transformations after '/upload/'
    return imageUrl.replace('/upload/', `/upload/${transformations}/`);
};

/**
 * Get thumbnail URL (200x200)
 */
const getThumbnailUrl = (imageUrl) => {
    return getOptimizedImageUrl(imageUrl, { width: 200, height: 200, crop: 'fill' });
};

/**
 * Get medium URL (600x600)
 */
const getMediumUrl = (imageUrl) => {
    return getOptimizedImageUrl(imageUrl, { width: 600, height: 600 });
};

module.exports = {
    deleteCloudinaryImage,
    deleteCloudinaryImages,
    getOptimizedImageUrl,
    getThumbnailUrl,
    getMediumUrl
};
