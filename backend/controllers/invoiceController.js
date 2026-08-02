'use strict';

/**
 * invoiceController.js — CRUD for GST Sales Invoices
 *
 * Math rules (re-validated server-side on every save):
 *   – Row taxable = (netWeight × rate) + makingCharge  [or manual override]
 *   – Row GST     = taxable × 1.5% CGST + 1.5% SGST  [or 3% IGST for inter-state]
 *   – Row total   = taxable + GST
 *   – Sum         = Σ rowTotal
 *   – Discount reduces payable AFTER GST — never touches GST base
 *   – Round-off   = Math.round(payable) − payable  [always ±₹0.50 max]
 */

const { getShopmanageConnection } = require('../config/db');
const { getNowIST } = require('../utils/gstHelpers');

let _Invoice, _GstConfig;

function getInvoiceModel() {
    if (!_Invoice) _Invoice = require('../models/Invoice')(getShopmanageConnection());
    return _Invoice;
}
function getGstConfigModel() {
    if (!_GstConfig) _GstConfig = require('../models/GstConfig')(getShopmanageConnection());
    return _GstConfig;
}

// ─── Auto-generate invoice number ─────────────────────────────────────────────
async function generateInvoiceNumber(Invoice) {
    const now   = new Date();
    const yy    = String(now.getFullYear()).slice(-2);
    const mm    = String(now.getMonth() + 1).padStart(2, '0');
    const prefix = `LGP-${yy}${mm}-`;

    // Find highest serial for this month
    const last = await Invoice.findOne(
        { invoiceNumber: { $regex: `^${prefix}` } },
        { invoiceNumber: 1 },
        { sort: { invoiceNumber: -1 } }
    ).lean();

    let seq = 1;
    if (last) {
        const parts = last.invoiceNumber.split('-');
        seq = parseInt(parts[parts.length - 1], 10) + 1;
    }
    return `${prefix}${String(seq).padStart(4, '0')}`;
}

// ─── POST /api/invoices ───────────────────────────────────────────────────────
exports.createInvoice = async (req, res) => {
    try {
        const Invoice   = getInvoiceModel();
        const GstConfig = getGstConfigModel();

        const gstCfg = await GstConfig.findOne({ isActive: true }).lean() || {};

        const {
            invoiceDate, deliveryDate, transactionType, reverseCharge,
            termsOfDelivery, placeOfSupply, goldRate, silverRate,
            customerName, customerMobile, customerAddress, customerPan,
            items = [], additionalCharges = 0, discount = 0,
            totalPayableOverridden = false, totalPayable: manualTotal,
            paidAmount = 0, paymentMode = 'cash',
            notes = '', attachments = [],
        } = req.body;

        if (!customerName) {
            return res.status(400).json({ success: false, message: 'customerName is required' });
        }
        if (!invoiceDate) {
            return res.status(400).json({ success: false, message: 'invoiceDate is required' });
        }

        // Build item sub-docs — compute taxable from rates if not overridden
        const builtItems = (items || []).map(item => {
            const rate = item.metalType === 'silver' ? (silverRate || 0) : (goldRate || 0);
            const taxable = item.taxableOverridden
                ? (item.taxableAmount || 0)
                : parseFloat(((item.netWeight || 0) * rate + (item.makingCharge || 0)).toFixed(2));
            return {
                particulars: item.particulars || '',
                hsnCode: item.hsnCode || gstCfg.hsnCode || '7113',
                metalType: item.metalType || 'gold',
                netWeight: item.netWeight || 0,
                makingCharge: item.makingCharge || 0,
                taxableAmount: taxable,
                taxableOverridden: !!item.taxableOverridden,
            };
        });

        const invoiceNumber = req.body.invoiceNumber || await generateInvoiceNumber(Invoice);

        const invoice = new Invoice({
            invoiceNumber,
            seller: {
                firmName:  gstCfg.firmName  || 'Laltu Guinea Palace',
                gstin:     gstCfg.gstin     || '',
                pan:       gstCfg.pan       || '',
                stateCode: gstCfg.stateCode || '19',
                state:     'West Bengal',
            },
            invoiceDate:   new Date(invoiceDate),
            deliveryDate:  deliveryDate ? new Date(deliveryDate) : null,
            transactionType:  transactionType  || gstCfg.defaultTransactionType || 'intra-state',
            reverseCharge:    !!reverseCharge,
            termsOfDelivery:  termsOfDelivery  || 'Customer Pickup',
            placeOfSupply:    placeOfSupply     || 'West Bengal',
            goldRate:   goldRate   || 0,
            silverRate: silverRate || 0,
            customerName, customerMobile, customerAddress, customerPan,
            items: builtItems,
            additionalCharges: additionalCharges || 0,
            discount: discount || 0,
            totalPayableOverridden,
            paidAmount:  paidAmount  || 0,
            paymentMode: paymentMode || 'cash',
            notes, attachments,
            createdBy:     req.user.id,
            createdByName: req.user.name || '',
            updatedBy:     req.user.id,
            updatedByName: req.user.name || '',
            createdAtIST:  getNowIST(),
            updatedAtIST:  getNowIST(),
        });

        // If user manually set totalPayable, honour it
        if (totalPayableOverridden && manualTotal != null) {
            invoice.totalPayable = manualTotal;
        }

        invoice.recomputeTotals();

        // TDS: if payable > 2L and PAN missing, warn but don't block
        if (invoice.tdsApplicable && !customerPan) {
            return res.status(400).json({
                success: false,
                message: 'Customer PAN is required for invoices exceeding ₹2,00,000 (TDS - Sec 194Q)',
            });
        }

        await invoice.save();

        res.status(201).json({ success: true, message: 'Invoice created', data: { invoice } });
    } catch (err) {
        console.error('[Invoice] createInvoice error:', err);
        res.status(500).json({ success: false, message: 'Error creating invoice', error: err.message });
    }
};

// ─── GET /api/invoices ────────────────────────────────────────────────────────
exports.getInvoices = async (req, res) => {
    try {
        const Invoice = getInvoiceModel();
        const { status, startDate, endDate, customerMobile, page = 1, limit = 50 } = req.query;

        const filter = { isDeleted: false };
        if (status) filter.status = status;
        if (customerMobile) filter.customerMobile = customerMobile;
        if (startDate || endDate) {
            filter.invoiceDate = {};
            if (startDate) filter.invoiceDate.$gte = new Date(startDate);
            if (endDate) {
                const end = new Date(endDate);
                end.setHours(23, 59, 59, 999);
                filter.invoiceDate.$lte = end;
            }
        }

        const skip  = (parseInt(page) - 1) * parseInt(limit);
        const total = await Invoice.countDocuments(filter);
        const invoices = await Invoice.find(filter)
            .sort({ invoiceDate: -1 })
            .skip(skip)
            .limit(parseInt(limit))
            .lean();

        res.json({ success: true, data: { invoices, total, page: parseInt(page), limit: parseInt(limit) } });
    } catch (err) {
        console.error('[Invoice] getInvoices error:', err);
        res.status(500).json({ success: false, message: 'Error fetching invoices', error: err.message });
    }
};

// ─── GET /api/invoices/next-number ───────────────────────────────────────────
exports.getNextNumber = async (req, res) => {
    try {
        const Invoice = getInvoiceModel();
        const number = await generateInvoiceNumber(Invoice);
        res.json({ success: true, data: { invoiceNumber: number } });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Error generating invoice number', error: err.message });
    }
};

// ─── GET /api/invoices/:id ────────────────────────────────────────────────────
exports.getInvoice = async (req, res) => {
    try {
        const Invoice   = getInvoiceModel();
        const invoice   = await Invoice.findOne({ _id: req.params.id, isDeleted: false }).lean();
        if (!invoice) return res.status(404).json({ success: false, message: 'Invoice not found' });
        res.json({ success: true, data: { invoice } });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Error fetching invoice', error: err.message });
    }
};

// ─── PUT /api/invoices/:id ────────────────────────────────────────────────────
exports.updateInvoice = async (req, res) => {
    try {
        const Invoice = getInvoiceModel();
        const invoice = await Invoice.findOne({ _id: req.params.id, isDeleted: false });
        if (!invoice) return res.status(404).json({ success: false, message: 'Invoice not found' });

        const allowedFields = [
            'invoiceDate', 'deliveryDate', 'transactionType', 'reverseCharge',
            'termsOfDelivery', 'placeOfSupply', 'goldRate', 'silverRate',
            'customerName', 'customerMobile', 'customerAddress', 'customerPan',
            'items', 'additionalCharges', 'discount',
            'totalPayableOverridden', 'totalPayable',
            'paidAmount', 'paymentMode', 'notes', 'attachments',
        ];

        for (const field of allowedFields) {
            if (req.body[field] !== undefined) {
                invoice[field] = req.body[field];
            }
        }

        // Re-derive item taxable values for non-overridden rows
        if (req.body.items) {
            const goldRate   = invoice.goldRate   || 0;
            const silverRate = invoice.silverRate || 0;
            for (const item of invoice.items) {
                if (!item.taxableOverridden) {
                    const rate = item.metalType === 'silver' ? silverRate : goldRate;
                    item.taxableAmount = parseFloat(
                        ((item.netWeight || 0) * rate + (item.makingCharge || 0)).toFixed(2)
                    );
                }
            }
        }

        invoice.updatedBy     = req.user.id;
        invoice.updatedByName = req.user.name || '';
        invoice.updatedAtIST  = getNowIST();

        invoice.recomputeTotals();

        if (invoice.tdsApplicable && !invoice.customerPan) {
            return res.status(400).json({
                success: false,
                message: 'Customer PAN is required for invoices exceeding ₹2,00,000 (TDS - Sec 194Q)',
            });
        }

        await invoice.save();
        res.json({ success: true, message: 'Invoice updated', data: { invoice } });
    } catch (err) {
        console.error('[Invoice] updateInvoice error:', err);
        res.status(500).json({ success: false, message: 'Error updating invoice', error: err.message });
    }
};

// ─── DELETE /api/invoices/:id (soft delete) ───────────────────────────────────
exports.deleteInvoice = async (req, res) => {
    try {
        const Invoice = getInvoiceModel();
        const invoice = await Invoice.findOne({ _id: req.params.id, isDeleted: false });
        if (!invoice) return res.status(404).json({ success: false, message: 'Invoice not found' });

        invoice.isDeleted     = true;
        invoice.updatedBy     = req.user.id;
        invoice.updatedAtIST  = getNowIST();
        await invoice.save();

        res.json({ success: true, message: 'Invoice deleted' });
    } catch (err) {
        res.status(500).json({ success: false, message: 'Error deleting invoice', error: err.message });
    }
};
