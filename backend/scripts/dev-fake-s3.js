'use strict';
/**
 * A throw-away S3 for local development:  node scripts/dev-fake-s3.js   (listens on 127.0.0.1:9199, keeps files in memory)
 * Start the dev API with  S3_BUCKET=dev-bucket S3_ENDPOINT=http://127.0.0.1:9199 S3_REGION=ap-south-1  to try uploads (login screen
 * pictures, item photos) without AWS and without touching Cloudinary. Files vanish when this stops.
 */
const { fake, objects } = require('./fake-s3');
const PORT = Number(process.env.FAKE_S3_PORT) || 9199;
fake.listen(PORT, '127.0.0.1', () => console.log(`fake S3 on http://127.0.0.1:${PORT} (in memory)`));
setInterval(() => {}, 1 << 30);
process.on('SIGINT', () => { console.log(`stopping; ${objects.size} object(s) dropped`); process.exit(0); });
