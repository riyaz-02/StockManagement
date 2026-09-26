/**
 * directoryValidators.js — validation + normalisation rules for the User
 * Directory. The mobile app applies the same rules for instant feedback, but
 * THIS file is the source of truth (the API never trusts the client).
 */
'use strict';

const str = (v) => (typeof v === 'string' ? v.trim() : v == null ? '' : String(v).trim());

// Keep digits only; drop a leading India country code / trunk zero so
// "+91 98765-43210", "098765 43210" and "9876543210" all compare equal.
function normalizePhone(v) {
    let d = str(v).replace(/\D/g, '');
    if (d.length === 12 && d.startsWith('91')) d = d.slice(2);
    if (d.length === 11 && d.startsWith('0')) d = d.slice(1);
    return d;
}
// Indian mobiles start 6-9; landlines/others are allowed via isValidAnyPhone.
const isMobile10 = (d) => /^[6-9]\d{9}$/.test(d);
const isPhone10 = (d) => /^\d{10}$/.test(d);

const isPAN = (v) => /^[A-Z]{5}[0-9]{4}[A-Z]$/.test(str(v).toUpperCase());
const isGSTIN = (v) => /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(str(v).toUpperCase());
const isAadhaar = (v) => /^[2-9]\d{11}$/.test(str(v).replace(/\s/g, ''));
const isIFSC = (v) => /^[A-Z]{4}0[A-Z0-9]{6}$/.test(str(v).toUpperCase());
const isPincode = (v) => /^[1-9]\d{5}$/.test(str(v));
const isEmail = (v) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(str(v));

// GST state codes (first two digits of a GSTIN).
const GST_STATE = {
    '01': 'Jammu & Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh', '05': 'Uttarakhand',
    '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim',
    '12': 'Arunachal Pradesh', '13': 'Nagaland', '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura',
    '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand', '21': 'Odisha',
    '22': 'Chhattisgarh', '23': 'Madhya Pradesh', '24': 'Gujarat', '26': 'Dadra & Nagar Haveli and Daman & Diu',
    '27': 'Maharashtra', '29': 'Karnataka', '30': 'Goa', '31': 'Lakshadweep', '32': 'Kerala',
    '33': 'Tamil Nadu', '34': 'Puducherry', '35': 'Andaman & Nicobar Islands', '36': 'Telangana',
    '37': 'Andhra Pradesh', '38': 'Ladakh',
};

/**
 * Validate optional identity/address fields shared by every record kind.
 * Returns an error message, or null when everything supplied is valid.
 * Empty values are always accepted (these fields are optional).
 */
function validateCommon(b) {
    if (str(b.email) && !isEmail(b.email)) return 'Email address is not valid';
    if (str(b.panNo) && !isPAN(b.panNo)) return 'PAN must look like ABCDE1234F';
    if (str(b.gstNo) && !isGSTIN(b.gstNo)) return 'GST number is not valid (15 characters)';
    if (str(b.aadharNo) && !isAadhaar(b.aadharNo)) return 'Aadhaar must be 12 digits';
    if (str(b.pincode) && !isPincode(b.pincode)) return 'Pincode must be 6 digits';
    if (str(b.gstNo) && str(b.panNo) && str(b.gstNo).toUpperCase().slice(2, 12) !== str(b.panNo).toUpperCase()) {
        return 'PAN does not match the PAN inside the GST number';
    }
    const bank = b.bank || (b.employment && b.employment.bank) || {};
    if (str(bank.ifsc) && !isIFSC(bank.ifsc)) return 'IFSC code is not valid (e.g. SBIN0001234)';
    if (str(b.dob)) {
        const d = new Date(b.dob);
        if (Number.isNaN(d.getTime())) return 'Date of birth is not valid';
        if (d > new Date()) return 'Date of birth cannot be in the future';
    }
    return null;
}

module.exports = {
    str, normalizePhone, isMobile10, isPhone10,
    isPAN, isGSTIN, isAadhaar, isIFSC, isPincode, isEmail,
    GST_STATE, validateCommon,
};
