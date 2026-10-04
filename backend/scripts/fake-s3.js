'use strict';
/** A tiny S3-compatible server for tests (single PUT, multipart, DeleteObjects, GET, DELETE). Not for production: no auth, in memory. */
const http = require('http');
const crypto = require('crypto');

const objects = new Map();   // "bucket/key" -> {body, type}
const uploads = new Map();   // uploadId -> {key, parts: Map}
const fake = http.createServer((req, res) => {
    const u = new URL(req.url, 'http://x');
    const p = decodeURIComponent(u.pathname).replace(/^\//, '');
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
        const body = Buffer.concat(chunks);
        const send = (code, text = '', headers = {}) => { res.writeHead(code, headers); res.end(text); };
        if (req.method === 'PUT' && u.searchParams.has('partNumber')) {
            const up = uploads.get(u.searchParams.get('uploadId'));
            const etag = `"${crypto.createHash('md5').update(body).digest('hex')}"`;
            up.parts.set(Number(u.searchParams.get('partNumber')), body);
            return send(200, '', { ETag: etag });
        }
        if (req.method === 'PUT') { objects.set(p, { body, type: req.headers['content-type'], cache: req.headers['cache-control'] }); return send(200, '', { ETag: '"x"' }); }
        if (req.method === 'POST' && u.searchParams.has('uploads')) {
            const id = crypto.randomBytes(6).toString('hex');
            uploads.set(id, { key: p, parts: new Map(), type: req.headers['content-type'] });
            return send(200, `<?xml version="1.0"?><InitiateMultipartUploadResult><Bucket>b</Bucket><Key>k</Key><UploadId>${id}</UploadId></InitiateMultipartUploadResult>`, { 'Content-Type': 'application/xml' });
        }
        if (req.method === 'POST' && u.searchParams.has('uploadId')) {
            const up = uploads.get(u.searchParams.get('uploadId'));
            const all = Buffer.concat([...up.parts.entries()].sort((a, b) => a[0] - b[0]).map((x) => x[1]));
            objects.set(up.key, { body: all, type: up.type });
            return send(200, '<?xml version="1.0"?><CompleteMultipartUploadResult><Location>x</Location><Bucket>b</Bucket><Key>k</Key><ETag>"y"</ETag></CompleteMultipartUploadResult>', { 'Content-Type': 'application/xml' });
        }
        if (req.method === 'POST' && u.searchParams.has('delete')) {
            const keys = [...body.toString().matchAll(/<Key>([^<]+)<\/Key>/g)].map((m) => m[1]);
            const bucket = p.split('/')[0];
            keys.forEach((k) => objects.delete(`${bucket}/${k}`));
            return send(200, '<?xml version="1.0"?><DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' + keys.map((k) => `<Deleted><Key>${k}</Key></Deleted>`).join('') + '</DeleteResult>', { 'Content-Type': 'application/xml' });
        }
        if (req.method === 'GET') { const o = objects.get(p); return o ? send(200, o.body, { 'Content-Type': o.type }) : send(404); }
        if (req.method === 'DELETE') { objects.delete(p); return send(204); }
        send(400);
    });
});


module.exports = { fake, objects, uploads };
