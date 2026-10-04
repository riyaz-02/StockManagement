/**
 * apkInfo.js - reads the package name, version name and version code out of an Android APK, so an uploaded update is
 * described by the file itself and never by what somebody typed (a wrong number would make phones never update, or
 * update forever).
 *
 * An APK is a zip; its AndroidManifest.xml is in Android's compiled binary XML ("AXML"): a string pool, a table of
 * resource ids for the attribute names, then the elements. Only the first element, <manifest>, is needed.
 */
'use strict';
const JSZip = require('jszip');

const RES_VERSION_CODE = 0x0101021b;
const RES_VERSION_NAME = 0x0101021c;

function readStringPool(b, at) {
    const hdr = b.readUInt16LE(at + 2);
    const count = b.readUInt32LE(at + 8);
    const flags = b.readUInt32LE(at + 16);
    const strStart = b.readUInt32LE(at + 20);
    const utf8 = (flags & 0x100) !== 0;
    const out = [];
    for (let i = 0; i < count; i++) {
        let p = at + strStart + b.readUInt32LE(at + hdr + i * 4);
        if (utf8) {
            let n = b[p++]; if (n & 0x80) n = ((n & 0x7f) << 8) | b[p++];       // length in characters
            let m = b[p++]; if (m & 0x80) m = ((m & 0x7f) << 8) | b[p++];       // length in bytes
            out.push(b.toString('utf8', p, p + m));
        } else {
            let n = b.readUInt16LE(p); p += 2; if (n & 0x8000) { n = ((n & 0x7fff) << 16) | b.readUInt16LE(p); p += 2; }
            out.push(b.toString('utf16le', p, p + n * 2));
        }
    }
    return out;
}

/** The <manifest> attributes of a compiled AndroidManifest.xml. */
function parseManifest(b) {
    if (b.length < 16 || b.readUInt16LE(0) !== 0x0003) throw new Error('This is not a compiled Android manifest');
    let pos = b.readUInt16LE(2);
    let strings = [];
    let resIds = [];
    while (pos + 8 <= b.length) {
        const type = b.readUInt16LE(pos), size = b.readUInt32LE(pos + 4);
        if (size < 8) break;
        if (type === 0x0001) strings = readStringPool(b, pos);
        else if (type === 0x0180) { for (let i = pos + 8; i + 4 <= pos + size; i += 4) resIds.push(b.readUInt32LE(i)); }
        else if (type === 0x0102) {
            const name = strings[b.readInt32LE(pos + 20)];
            if (name === 'manifest') {
                const attrStart = b.readUInt16LE(pos + 24), attrSize = b.readUInt16LE(pos + 26), attrCount = b.readUInt16LE(pos + 28);
                const info = {};
                for (let i = 0; i < attrCount; i++) {
                    const a = pos + 16 + attrStart + i * attrSize;
                    const nameIdx = b.readInt32LE(a + 4), raw = b.readInt32LE(a + 8), dataType = b[a + 15], data = b.readUInt32LE(a + 16);
                    const key = strings[nameIdx], res = resIds[nameIdx];
                    const value = raw >= 0 ? strings[raw] : dataType === 0x10 || dataType === 0x11 ? data : dataType === 0x03 ? strings[data] : data;
                    if (res === RES_VERSION_CODE || key === 'versionCode') info.versionCode = Number(value);
                    else if (res === RES_VERSION_NAME || key === 'versionName') info.versionName = String(value);
                    else if (key === 'package') info.package = String(value);
                }
                return info;
            }
        }
        pos += size;
    }
    throw new Error('The manifest has no <manifest> element');
}

/** {package, versionName, versionCode} of an APK (a Buffer). Throws a readable error for anything that is not an APK. */
async function readApk(buffer) {
    if (!buffer || buffer.length < 4 || buffer[0] !== 0x50 || buffer[1] !== 0x4b) throw new Error('This file is not an APK (it is not a zip file)');
    let zip;
    try { zip = await JSZip.loadAsync(buffer); } catch (e) { throw new Error('This file is not a valid APK (the zip is damaged)'); }
    const entry = zip.file('AndroidManifest.xml');
    if (!entry) throw new Error('This file is not an Android app (there is no AndroidManifest.xml inside)');
    const info = parseManifest(await entry.async('nodebuffer'));
    if (!info.package || !Number.isInteger(info.versionCode) || !info.versionName) throw new Error('The APK does not say its package, version name and version code');
    return { package: info.package, versionName: info.versionName, versionCode: info.versionCode, signed: !!Object.keys(zip.files).find((n) => /^META-INF\/.+\.(RSA|DSA|EC)$/i.test(n)) };
}

module.exports = { readApk, parseManifest };
