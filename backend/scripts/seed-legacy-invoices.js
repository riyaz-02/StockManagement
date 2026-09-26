/**
 * seed-legacy-invoices.js — puts a few invoices shaped EXACTLY like the ones the
 * live LGPManagement website writes (snake_case, shop_info counter at 1759)
 * into the LOCAL test database, so the app's billing can be tried against
 * "what is already there". Synthetic names only. Refuses to touch anything
 * that is not localhost.
 *
 *   node scripts/seed-legacy-invoices.js          (also called by local-db.js)
 */
'use strict';

const { MongoClient } = require('mongodb');

async function seedLegacyInvoices(uri, dbName = 'lgp_dev') {
    if (!/(localhost|127\.0\.0\.1)/.test(uri)) throw new Error('seed-legacy-invoices only runs against a local database');
    const client = await MongoClient.connect(uri);
    try {
        const db = client.db(dbName);
        if ((await db.collection('invoices').estimatedDocumentCount()) > 0) return false;

        const pay = (amount, date, mode = 'Cash', ref = '') => ({
            amount, payment_mode: mode, transaction_reference: ref, description: 'Payment at the time of invoice creation',
            payment_date: date, payment_time: '17:45:10', created_at: new Date(`${date}T12:15:10.000Z`), created_by: '6839a77454ab13b05c006d73', files: [],
        });
        const base = (n, date, name, mobile, extra) => ({
            invoice_number: n, invoice_date: date, customer_name: name, customer_address: 'Chandannagar', customer_mobile: mobile,
            customer_id: '', customer_pan: '', customer_state: 'West Bengal', customer_state_code: '19', place_of_supply: '19-West Bengal',
            reverse_charge: 'No', terms_of_delivery: 'Customer Pickup', reference: '', lgp_wallet: 0, delivery_date: date,
            gold_rate: 9190, silver_rate: 110, additional_charges: 0, discount: 0, round_off: 0, note: '', paid_amount: 0, payment_mode: 'Cash',
            due_advance: 0, tds_applicable: false, tds_rate: 0, tds_amount: 0, status: 'delivered', print_status: 0, pay_no: 0, payment_history: [],
            created_at: new Date(`${date}T08:00:00.000Z`), ...extra,
        });
        const item = (particulars, metal, wt, rate, making, taxable) => {
            const cg = Math.round(taxable * 0.015 * 100) / 100;
            return { particulars, hsn_code: '7113', metal_type: metal, net_wt: wt, rate, making_charge: making, taxable_amount: taxable, cgst: cg, sgst: cg, total: Math.round((taxable + 2 * taxable * 0.015) * 100) / 100 };
        };

        const docs = [
            // a plain invoice, like real invoice 1401
            base('1401', '2025-06-10', 'Legacy Customer A', '9000000101', {
                items: [item('Gold Chain', 'Gold', 0.08, 9190, 64, 799.2)], additional_charges: 55, total_amount: 878.18, discount: 78, round_off: -0.18,
                total_payable_amount: 800, amount_in_words: 'Eight Hundred Rupees Only (আটশত টাকা মাত্র)', paid_amount: 800, pay_no: 1, payment_history: [pay(800, '2025-06-10')],
                gst_summary: { total_taxable_amount: 799.2, total_cgst: 11.99, total_sgst: 11.99, total_gst: 23.98 }, print_status: 1,
            }),
            // staff typed the taxable amount by hand (negotiated price), like real invoice 1423
            base('1423', '2025-06-14', 'Legacy Customer B', '9000000102', {
                items: [item('Silver Anklet', 'Silver', 22.6, 105, 0, 2600)], total_amount: 2678, discount: 78, total_payable_amount: 2600,
                amount_in_words: 'Two Thousand Six Hundred Rupees Only', paid_amount: 2600, pay_no: 1, payment_history: [pay(2600, '2025-06-14', 'Online', 'UTR1')],
                gst_summary: { total_taxable_amount: 2600, total_cgst: 39, total_sgst: 39, total_gst: 78 },
            }),
            // part paid, delivered -> active, with a due balance
            base('1500', '2025-07-02', 'Legacy Customer C', '9000000103', {
                items: [item('Gold Bangle', 'Gold', 5, 9000, 500, 45500)], total_amount: 46865, total_payable_amount: 46865, amount_in_words: 'Forty Six Thousand Eight Hundred and Sixty Five Rupees Only',
                paid_amount: 20000, due_advance: -26865, status: 'active', pay_no: 1, payment_history: [pay(20000, '2025-07-02')],
                gst_summary: { total_taxable_amount: 45500, total_cgst: 682.5, total_sgst: 682.5, total_gst: 1365 },
            }),
            // hand-written block bill: no rates, no customer
            base('1-100', '2025-06-13', 'Bill Block A (1-100)', '', {
                customer_address: 'Bulk Bill Hand Writtern', gold_rate: 0, silver_rate: 0, items: [{ particulars: 'Gold Mixed Ornaments', metal_type: 'Gold', net_wt: 42.74, rate: 0, making_charge: 0, taxable_amount: 0, cgst: 0, sgst: 0, total: 0 }],
                total_amount: 0, total_payable_amount: 0, amount_in_words: '0.00 Rupees Only (0.00 টাকা মাত্র)', created_at: '2025-06-13T09:07:55.253Z',
                gst_summary: { cgst_rate: 1.5, sgst_rate: 1.5, total_cgst: 0, total_sgst: 0, total_gst: 0 },
            }),
            // a cancelled invoice
            base('1450', '2025-06-20', 'Legacy Customer D', '9000000104', {
                items: [item('Gold Ring', 'Gold', 2, 9100, 200, 18400)], total_amount: 18952, total_payable_amount: 18952, paid_amount: 18952, status: 'cancelled',
                pay_no: 1, payment_history: [pay(18952, '2025-06-20')], status_reason: 'test', gst_summary: { total_taxable_amount: 18400, total_cgst: 276, total_sgst: 276, total_gst: 552 },
            }),
            // the most recent one
            base('1759', '2025-09-15', 'Legacy Customer E', '9000000105', {
                items: [item('Silver Chain', 'Silver', 30, 110, 100, 3400)], total_amount: 3502, total_payable_amount: 3502, paid_amount: 3502, pay_no: 1, payment_history: [pay(3502, '2025-09-15')],
                gst_summary: { total_taxable_amount: 3400, total_cgst: 51, total_sgst: 51, total_gst: 102 },
            }),
        ];
        await db.collection('invoices').insertMany(docs);

        // the website's numbering document (the last real number is 1759)
        await db.collection('shop_info').updateOne({ shop_id: 'default' }, { $setOnInsert: { shop_id: 'default', last_invoice_number: 1759, created_at: new Date() } }, { upsert: true });
        return true;
    } finally {
        await client.close();
    }
}

module.exports = { seedLegacyInvoices };

if (require.main === module) {
    seedLegacyInvoices(process.env.LOCAL_MONGO || 'mongodb://127.0.0.1:27018')
        .then((did) => console.log(did ? 'Seeded 6 legacy-shaped invoices + shop_info (last number 1759).' : 'invoices already present - nothing seeded.'))
        .catch((e) => { console.error(e.message); process.exit(1); });
}
