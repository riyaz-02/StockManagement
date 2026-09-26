/**
 * DirectoryStaffProfile.js — HR profile for a staff member (personal,
 * education, employment). NEW collection `app_staff_profiles`; deliberately
 * separate from the legacy `users` login collection.
 */
const mongoose = require('mongoose');

const schema = new mongoose.Schema(
    {
        branchId: { type: String, default: 'main' },
        branchName: { type: String, default: 'Main branch' },
        firstName: { type: String, required: true, trim: true },
        lastName: { type: String, trim: true },
        dob: Date,
        gender: { type: String, enum: ['M', 'F', ''], default: 'M' },
        mobile: { type: String, required: true, trim: true },
        phone: { type: String, trim: true },
        email: { type: String, trim: true },
        maritalStatus: { type: String, trim: true },
        emergencyContactName: { type: String, trim: true },
        emergencyContactPhone: { type: String, trim: true },
        address: { type: String, trim: true },
        city: { type: String, trim: true },
        state: { type: String, trim: true },
        country: { type: String, trim: true, default: 'India' },
        pincode: { type: String, trim: true },
        panNo: { type: String, trim: true, uppercase: true },
        aadharNo: { type: String, trim: true },
        education: { degree: String, institution: String, passingYear: String, certifications: String },
        employment: {
            department: String,
            designation: String,
            salary: Number,
            startDate: Date,
            bank: { name: String, accountName: String, accountNo: String, ifsc: { type: String, uppercase: true } },
            previousCompany: String,
            previousDesignation: String,
        },
        updatedBy: String,
        updatedByName: String,
        createdBy: String,
        createdByName: String,
    },
    { collection: 'app_staff_profiles', versionKey: false, timestamps: true, autoIndex: false, autoCreate: false }
);

module.exports = (conn) => conn.models.DirectoryStaffProfile || conn.model('DirectoryStaffProfile', schema);
