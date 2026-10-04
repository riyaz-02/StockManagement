/**
 * billingView.js — turns a document from the LIVE `invoices` collection
 * (snake_case, written by the LGPManagement website and by this app) into the
 * shape the mobile app shows.
 *
 * Real data is messy, so this never assumes: numbers may be strings, dates may
 * be Date objects or text, fields may be missing. Old invoices (hand-written
 * "block" bills, the earlier gst_summary layout, etc.) must all display.
 */
'use strict';

const num = (v) => {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
};
const r2 = (n) => Math.round((num(n) + Number.EPSILON) * 100) / 100;
const str = (v) => (v == null ? '' : String(v));

const isoOf = (v) => {
    if (!v) return '';
    if (v instanceof Date) return Number.isNaN(v.getTime()) ? '' : v.toISOString();
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? str(v) : d.toISOString();
};

// payment_date "YYYY-MM-DD" + payment_time "HH:MM:SS" are India local time.
function paymentWhen(p) {
    if (p.created_at instanceof Date) return p.created_at.toISOString();
    if (p.payment_date) {
        const d = new Date(`${p.payment_date}T${p.payment_time || '00:00:00'}+05:30`);
        if (!Number.isNaN(d.getTime())) return d.toISOString();
    }
    return isoOf(p.created_at);
}

const HIDDEN_STATUSES = ['cancelled', 'void', 'deleted'];

function toView(d) {
    const payable = num(d.total_payable_amount);
    const paid = num(d.paid_amount);
    // Use payable - paid rather than the stored due_advance, which older invoices may not carry.
    const gap = r2(payable - paid);
    const items = (Array.isArray(d.items) ? d.items : []).map((i) => ({
        particular: str(i.particulars || i.particular),
        hsnCode: str(i.hsn_code),
        metalType: str(i.metal_type),
        netWt: num(i.net_wt),
        rate: num(i.rate),
        makingCharge: num(i.making_charge),
        taxableAmount: num(i.taxable_amount),
        cgst: num(i.cgst),
        sgst: num(i.sgst),
        igst: num(i.igst),
        total: num(i.total),
        purity: str(i.purity),
        grossWt: num(i.gross_wt),
        productCode: str(i.product_code),
        huid: str(i.huid),
        itemId: str(i.item_id),
        stoneCharge: num(i.stone_charge),
        certification: str(i.certification),
        hallmarkCharge: num(i.hallmark_charge),
        hallmarkTaxed: i.hallmark_in_taxable !== false,           // bills before rule v3 had the hallmark fee inside the taxable amount; since v3 it is added after tax
        itemName: str(i.item_name),
        discount: num(i.discount),
        extras: (Array.isArray(i.extras) ? i.extras : []).map((e) => ({ kind: str(e.kind), name: str(e.name), weight: num(e.weight), amount: num(e.amount) })),
    }));
    const gs = d.gst_summary || {};
    const sumTax = items.reduce((a, i) => a + i.taxableAmount, 0);
    const sumCgst = items.reduce((a, i) => a + i.cgst, 0);
    const sumSgst = items.reduce((a, i) => a + i.sgst, 0);
    const sumIgst = items.reduce((a, i) => a + i.igst, 0);
    const cgst = gs.total_cgst != null ? num(gs.total_cgst) : sumCgst;
    const sgst = gs.total_sgst != null ? num(gs.total_sgst) : sumSgst;

    const customerId = str(d.customer_id);
    return {
        _id: str(d._id),
        invoiceNumber: str(d.invoice_number),
        invoiceDate: str(d.invoice_date),
        deliveryDate: str(d.delivery_date),
        customerName: str(d.customer_name),
        customerNameBn: '',
        customerAddress: str(d.customer_address),
        customerMobile: str(d.customer_mobile),
        Customer_ID: str(d.customer_code) || customerId,
        customerObjectId: /^[0-9a-f]{24}$/i.test(customerId) ? customerId : '',
        walkIn: d.walk_in === true,
        customerPan: str(d.customer_pan),
        customerState: str(d.customer_state),
        customerStateCode: str(d.customer_state_code),
        placeOfSupply: str(d.place_of_supply),
        reverseCharge: str(d.reverse_charge),
        termsOfDelivery: str(d.terms_of_delivery),
        reference: str(d.reference),
        goldRate: num(d.gold_rate),
        silverRate: num(d.silver_rate),
        items,
        totalAmount: num(d.total_amount),
        additionalCharges: num(d.additional_charges),
        additionalChargesGst: num(d.additional_charges_gst),
        hallmarkTotal: num(d.hallmark_total),                       // hallmark / HUID fees passed on (rule v3): inside the total, outside the taxable value
        discount: num(d.discount),
        discountMode: str(d.discount_mode) || 'after_gst',        // old (website) invoices took it off after GST
        discountGiven: d.discount_given != null ? num(d.discount_given) : num(d.discount),
        discountBeforeGst: num(d.discount_before_gst),
        grossTaxable: d.gross_taxable != null ? num(d.gross_taxable) : 0,
        billBeforeDiscount: num(d.bill_before_discount),
        roundOff: num(d.round_off),
        totalPayableAmount: payable,
        amountInWords: str(d.amount_in_words),
        paidAmount: paid,
        dueAmount: gap > 0 ? gap : 0,
        advanceAmount: gap < 0 ? -gap : 0,
        paymentMode: str(d.payment_mode),
        note: str(d.note),
        oldMetal: (Array.isArray(d.old_metal) ? d.old_metal : []).map((o) => ({ id: str(o.id), metal: str(o.metal), purity: str(o.purity), net: num(o.net), fine: num(o.fine), rate: num(o.rate), amount: num(o.amount), customer: str(o.customer) })),
        oldMetalAmount: num(d.old_metal_amount),
        tds: { applicable: d.tds_applicable === true, rate: num(d.tds_rate), amount: num(d.tds_amount) },
        gstSummary: {
            taxableValue: gs.total_taxable_amount != null ? num(gs.total_taxable_amount) : r2(sumTax),
            cgst: r2(cgst), sgst: r2(sgst), igst: gs.total_igst != null ? r2(gs.total_igst) : r2(sumIgst),
            totalTax: gs.total_gst != null ? r2(gs.total_gst) : r2(cgst + sgst + sumIgst),
        },
        gstType: str(d.gst_type) || (sumIgst > 0 ? 'IGST' : 'CGST_SGST'),
        status: str(d.status) || 'pending',
        printStatus: num(d.print_status),
        revisionId: str(d.revision_id || d.amendment_id),
        paymentHistory: (Array.isArray(d.payment_history) ? d.payment_history : []).map((p) => ({
            amount: num(p.amount),
            date: paymentWhen(p),
            mode: str(p.payment_mode),
            reference: str(p.transaction_reference),
            description: str(p.description),
            receivedBy: str(p.created_by_name),
            requestId: str(p.request_id),
        })),
        branchId: str(d.branch_id) || 'main',
        branchName: str(d.branch_name) || 'Main branch',
        createdBy: str(d.created_by_name),
        createdAt: isoOf(d.created_at),
        source: str(d.source) || 'website',
        counts: !HIDDEN_STATUSES.includes(str(d.status)),   // cancelled / void / deleted are excluded from totals
    };
}

/** Row for the list screen (a small subset of toView), plus a cheap summary of what's on the bill (items were already parsed by toView). */
function toRow(d) {
    const v = toView(d);
    const weight = {};
    for (const it of v.items) { const m = it.metalType || 'Other'; weight[m] = Math.round(((weight[m] || 0) + (it.netWt || 0)) * 1000) / 1000; }
    return {
        _id: v._id, invoiceNumber: v.invoiceNumber, invoiceDate: v.invoiceDate, customerName: v.customerName,
        customerNameBn: v.customerNameBn, customerMobile: v.customerMobile, Customer_ID: v.Customer_ID, walkIn: v.walkIn,
        totalPayableAmount: v.totalPayableAmount, paidAmount: v.paidAmount, dueAmount: v.dueAmount, advanceAmount: v.advanceAmount,
        branchName: v.branchName, createdBy: v.createdBy, createdAt: v.createdAt, paymentMode: v.paymentMode,
        status: v.status, revisionId: v.revisionId,
        itemsSummary: { count: v.items.length, first: v.items[0] ? v.items[0].particular : '', weight },
    };
}

module.exports = { toView, toRow, HIDDEN_STATUSES };
