/**
 * DirectoryCustomerProfile.js — extra details for a customer. NEW collection
 * `app_customer_profiles`, linked to the legacy `customers` document by
 * `customerId`.
 *
 * Why separate: the legacy `customers` collection is production data shared
 * with the web admin. Only the fields it already knows are written there;
 * everything richer lives here so legacy documents stay exactly as the web
 * admin expects.
 *
 * Migration-friendly by design: field names/values follow the LGPAdmin
 * website's customer record (Customer_ID -> customerCode, Membership_Status,
 * Gender = Male|Female|Other, Name_Bn, Nickname_Bn, Address_Bn, Mobile_No1/2 ->
 * contacts[], Referred_By -> referredBy). See docs/customer-migration.md.
 */
const mongoose = require('mongoose');

const balance = { amount: { type: Number, default: 0 }, type: { type: String, enum: ['credit', 'debit'], default: 'credit' } };
const metal = { weight: { type: Number, default: 0 }, unit: { type: String, default: 'gram' }, type: { type: String, default: 'credit' } };

const contactSchema = new mongoose.Schema(
    {
        number: { type: String, required: true },           // normalised 10 digits
        label: { type: String, enum: ['whatsapp', 'mobile', 'home', 'work', 'other'], default: 'mobile' },
    },
    { _id: false }
);

const schema = new mongoose.Schema(
    {
        customerId: { type: mongoose.Schema.Types.ObjectId, required: true, index: true },
        // Stable, human-facing ID in the LGPAdmin format: LGP + yymmdd + 3 hex.
        customerCode: { type: String, required: true, uppercase: true, index: true },

        branchId: { type: String, default: 'main' },
        branchName: { type: String, default: 'Main branch' },

        membershipStatus: { type: String, enum: ['Regular', 'VIP'], default: 'Regular' },
        customerType: { type: String, trim: true },          // Retail, Wholesale, ... (optional extra)

        nicknameBn: { type: String, trim: true },
        addressBn: { type: String, trim: true },
        fatherName: { type: String, trim: true },            // S/O, D/O, W/O
        gender: { type: String, enum: ['Male', 'Female', 'Other', ''], default: '' },
        dob: Date,
        anniversary: Date,

        // Every phone number, primary first. contacts[0] is the WhatsApp number.
        contacts: [contactSchema],

        city: { type: String, trim: true },
        state: { type: String, trim: true },
        country: { type: String, trim: true, default: 'India' },
        pincode: { type: String, trim: true },

        // Referral: a link to an existing customer (preferred) and/or free text
        // (what the website stores today).
        referredBy: {
            customerId: mongoose.Schema.Types.ObjectId,
            code: String,
            name: String,
            mobile: String,
            text: String,
        },

        businessName: { type: String, trim: true },
        gstNo: { type: String, trim: true, uppercase: true },
        panNo: { type: String, trim: true, uppercase: true },
        aadharNo: { type: String, trim: true },
        taxNo: { type: String, trim: true },
        notes: { type: String, trim: true },
        profilePicUrl: { type: String, trim: true },

        opening: {
            date: Date,
            cash: balance,
            gold: metal,
            silver: metal,
        },

        // Provenance, so migrated and app-created rows can always be told apart.
        source: { type: String, default: 'app' },            // app | lgpadmin | shopmanage
        sourceId: { type: String },                          // original id in the source system

        createdBy: String,
        createdByName: String,
    },
    { collection: 'app_customer_profiles', versionKey: false, timestamps: true, autoIndex: false, autoCreate: false }
);

module.exports = (conn) => conn.models.DirectoryCustomerProfile || conn.model('DirectoryCustomerProfile', schema);
