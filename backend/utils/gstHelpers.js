/**
 * gstHelpers.js — Indian GST/TDS utility functions
 *
 * All calculations follow Indian tax law for Chapter 71
 * (Gold/Silver Jewelry & Articles):
 *   - GST: 3% (CGST 1.5% + SGST 1.5% for intra-state; IGST 3% for inter-state)
 *   - TDS: 1% under Section 194Q (only when amount > ₹2,00,000)
 *   - HSN: 7113 (≤₹1.5Cr turnover) or 71131100 (>₹1.5Cr turnover)
 */

'use strict';

// ─── Regex Validators ────────────────────────────────────────────────────────

/**
 * Validate a 15-character Indian GSTIN.
 * Format: <2-digit state code><PAN><1-digit entity><'Z'><1 check digit>
 * @param {string} gstin
 * @returns {boolean}
 */
function validateGSTIN(gstin) {
    if (!gstin || typeof gstin !== 'string') return false;
    const pattern = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$/;
    return pattern.test(gstin.toUpperCase().trim());
}

/**
 * Validate a 10-character Indian PAN.
 * Format: AAAAA9999A
 * @param {string} pan
 * @returns {boolean}
 */
function validatePAN(pan) {
    if (!pan || typeof pan !== 'string') return false;
    const pattern = /^[A-Z]{5}[0-9]{4}[A-Z]{1}$/;
    return pattern.test(pan.toUpperCase().trim());
}

/**
 * Validate an HSN code for Chapter 71 (precious metals/jewelry).
 * Accepts 4-digit (7113) or 8-digit (71131100) codes starting with 71.
 * @param {string} hsn
 * @returns {boolean}
 */
function validateHSN(hsn) {
    if (!hsn || typeof hsn !== 'string') return false;
    const trimmed = hsn.trim();
    // Must be numeric, 4 or 8 digits, and start with 71
    return /^71\d{2}(\d{4})?$/.test(trimmed);
}

// ─── HSN Selection ───────────────────────────────────────────────────────────

/**
 * Select the correct HSN code based on firm's annual turnover.
 * @param {'below_1_5cr'|'above_1_5cr'} turnoverCategory
 * @returns {string} HSN code
 */
function getHSNCode(turnoverCategory) {
    // Firms with turnover > ₹1.5 Cr must use 8-digit HSN (CBIC mandate)
    return turnoverCategory === 'above_1_5cr' ? '71131100' : '7113';
}

// ─── TDS Logic (Section 194Q) ────────────────────────────────────────────────

/**
 * Determine if TDS is applicable.
 * TDS is deducted ONLY when the transaction amount STRICTLY EXCEEDS ₹2,00,000.
 * @param {number} totalAmount — invoice total before TDS
 * @param {number} [threshold=200000]
 * @returns {boolean}
 */
function isTDSApplicable(totalAmount, threshold = 200000) {
    return totalAmount > threshold;
}

/**
 * Calculate TDS amount.
 * @param {number} totalAmount
 * @param {number} [tdsRate=1.0] — percentage
 * @param {number} [threshold=200000]
 * @returns {number} TDS amount (0 if not applicable)
 */
function calculateTDS(totalAmount, tdsRate = 1.0, threshold = 200000) {
    if (!isTDSApplicable(totalAmount, threshold)) return 0;
    return parseFloat(((totalAmount * tdsRate) / 100).toFixed(2));
}

// ─── GST Calculator ──────────────────────────────────────────────────────────

/**
 * Calculate complete GST breakdown for a purchase/sale transaction.
 *
 * @param {number} baseAmount     — Amount on which GST is calculated (before tax)
 * @param {object} config         — GST configuration
 * @param {number} config.gstRate          — Total GST rate (default 3.0)
 * @param {number} config.cgstRate         — CGST rate (default 1.5)
 * @param {number} config.sgstRate         — SGST rate (default 1.5)
 * @param {number} config.igstRate         — IGST rate (default 3.0)
 * @param {number} config.tdsRate          — TDS rate (default 1.0)
 * @param {number} config.tdsThreshold     — TDS threshold (default 200000)
 * @param {string} config.hsnCode          — HSN code
 * @param {'intra-state'|'inter-state'} transactionType
 *
 * @returns {{
 *   baseAmount: number,
 *   gstRate: number,
 *   cgst: {rate: number, amount: number} | null,
 *   sgst: {rate: number, amount: number} | null,
 *   igst: {rate: number, amount: number} | null,
 *   totalGst: number,
 *   totalWithGst: number,
 *   tdsApplicable: boolean,
 *   tdsRate: number,
 *   tdsAmount: number,
 *   netPayable: number,
 *   hsnCode: string
 * }}
 */
function calculateGST(baseAmount, config = {}, transactionType = 'intra-state') {
    const {
        gstRate = 3.0,
        cgstRate = 1.5,
        sgstRate = 1.5,
        igstRate = 3.0,
        tdsRate = 1.0,
        tdsThreshold = 200000,
        hsnCode = '7113',
    } = config;

    const base = parseFloat(baseAmount) || 0;

    let cgst = null;
    let sgst = null;
    let igst = null;
    let totalGst = 0;

    if (transactionType === 'intra-state') {
        // Split GST into CGST + SGST
        const cgstAmount = parseFloat(((base * cgstRate) / 100).toFixed(2));
        const sgstAmount = parseFloat(((base * sgstRate) / 100).toFixed(2));
        totalGst = parseFloat((cgstAmount + sgstAmount).toFixed(2));
        cgst = { rate: cgstRate, amount: cgstAmount };
        sgst = { rate: sgstRate, amount: sgstAmount };
    } else {
        // Inter-state: IGST only
        const igstAmount = parseFloat(((base * igstRate) / 100).toFixed(2));
        totalGst = igstAmount;
        igst = { rate: igstRate, amount: igstAmount };
    }

    const totalWithGst = parseFloat((base + totalGst).toFixed(2));

    // TDS is calculated on the taxable value (not on GST)
    const tdsApplicable = isTDSApplicable(base, tdsThreshold);
    const tdsAmount = tdsApplicable
        ? calculateTDS(base, tdsRate, tdsThreshold)
        : 0;

    // ── ITC (Input Tax Credit) ────────────────────────────────────────────────
    // In B2B transactions, the buyer can claim full ITC on GST paid to supplier.
    // The ITC is matched against the supplier's GSTR-1 via GSTR-2B/2A.
    const itcCgst  = cgst ? cgst.amount : 0;
    const itcSgst  = sgst ? sgst.amount : 0;
    const itcIgst  = igst ? igst.amount : 0;
    const totalItc = parseFloat((itcCgst + itcSgst + itcIgst).toFixed(2));

    // Total payable to supplier = taxable value + GST
    const totalPayable = totalWithGst;

    // Effective inventory cost = taxable value (GST is recovered via ITC)
    const effectiveCost = base;

    // Net cash outflow = (taxable + GST) - TDS deducted at source
    const netPayable = parseFloat((totalPayable - tdsAmount).toFixed(2));

    return {
        baseAmount: base,
        gstRate,
        cgst,
        sgst,
        igst,
        totalGst,
        totalWithGst,
        totalPayable,
        // ITC fields
        itcCgst,
        itcSgst,
        itcIgst,
        totalItc,
        effectiveCost,
        // TDS
        tdsApplicable,
        tdsRate,
        tdsAmount,
        netPayable,
        hsnCode,
    };
}

// ─── Indian Number Formatting ─────────────────────────────────────────────────

/**
 * Format a number in Indian currency system (lakhs/crores).
 * @param {number} amount
 * @returns {string} e.g., "₹1,23,456.78"
 */
function formatIndianCurrency(amount) {
    const num = parseFloat(amount) || 0;
    return '₹' + num.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/**
 * Convert a number to Indian words (for invoice printing).
 * Supports up to crores.
 * @param {number} amount
 * @returns {string} e.g., "One Lakh Twenty-Three Thousand Four Hundred Fifty-Six and Seventy-Eight Paise"
 */
function amountToWordsIndian(amount) {
    const ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
        'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen',
        'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
    const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

    function convertHundreds(n) {
        let result = '';
        if (n >= 100) {
            result += ones[Math.floor(n / 100)] + ' Hundred ';
            n %= 100;
        }
        if (n >= 20) {
            result += tens[Math.floor(n / 10)] + ' ';
            n %= 10;
        }
        if (n > 0) result += ones[n] + ' ';
        return result.trim();
    }

    const num = Math.floor(amount);
    const paise = Math.round((amount - num) * 100);

    if (num === 0) return 'Zero Rupees Only';

    let result = '';
    const crore = Math.floor(num / 10000000);
    const lakh = Math.floor((num % 10000000) / 100000);
    const thousand = Math.floor((num % 100000) / 1000);
    const remainder = num % 1000;

    if (crore > 0) result += convertHundreds(crore) + ' Crore ';
    if (lakh > 0) result += convertHundreds(lakh) + ' Lakh ';
    if (thousand > 0) result += convertHundreds(thousand) + ' Thousand ';
    if (remainder > 0) result += convertHundreds(remainder);

    result = result.trim() + ' Rupees';
    if (paise > 0) result += ' and ' + convertHundreds(paise).trim() + ' Paise';
    result += ' Only';

    return result.trim();
}

// ─── IST Timestamp Helper ─────────────────────────────────────────────────────

/**
 * Get current time formatted in IST (Asia/Kolkata).
 * @returns {string} e.g., "19/04/2026, 14:30:00 IST"
 */
function getNowIST() {
    return new Date().toLocaleString('en-IN', {
        timeZone: 'Asia/Kolkata',
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false,
    }) + ' IST';
}

/**
 * Normalize a date to start-of-day IST for consistent date comparisons.
 * @param {Date|string} date
 * @returns {Date}
 */
function normalizeToIST(date) {
    const d = new Date(date);
    // Convert to IST by adding +5:30
    const istOffset = 5.5 * 60 * 60 * 1000;
    const utcMs = d.getTime();
    const istMs = utcMs + istOffset;
    const istDate = new Date(istMs);
    // Zero out the time components
    return new Date(Date.UTC(
        istDate.getUTCFullYear(),
        istDate.getUTCMonth(),
        istDate.getUTCDate()
    ));
}

module.exports = {
    validateGSTIN,
    validatePAN,
    validateHSN,
    getHSNCode,
    isTDSApplicable,
    calculateTDS,
    calculateGST,
    formatIndianCurrency,
    amountToWordsIndian,
    getNowIST,
    normalizeToIST,
};
