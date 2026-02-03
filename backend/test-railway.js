// Quick test script to check if Railway backend is running
const https = require('https');

// Replace with your actual Railway URL
const RAILWAY_URL = 'YOUR_RAILWAY_URL_HERE';

console.log('Testing Railway backend...\n');

// Test health endpoint
https.get(`${RAILWAY_URL}/health`, (res) => {
    let data = '';

    res.on('data', (chunk) => {
        data += chunk;
    });

    res.on('end', () => {
        console.log('✅ Backend is RUNNING!');
        console.log('Status Code:', res.statusCode);
        console.log('Response:', data);
        console.log('\nCompression enabled:', res.headers['content-encoding'] === 'gzip' ? 'YES ✅' : 'NO ❌');
    });
}).on('error', (err) => {
    console.log('❌ Backend is DOWN or unreachable');
    console.log('Error:', err.message);
});
