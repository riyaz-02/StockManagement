// New bill / New estimate: instant totals, auto calculations and the same checks as the phone app.
// The bill maths is the server's own engine (billing-calc.js is generated from backend/services/billingCalc.js);
// the server calculates and checks everything again when the bill is saved.
(function () {
    'use strict';
    var form = document.getElementById('bill-form');
    if (!form || !window.BillingCalc) return;
    var C = window.BillingCalc;
    var isBill = form.dataset.mode === 'bill';
    var STATE = String(form.dataset.stateCode || '19');
    var CASH_LIMIT = Number(form.dataset.cashLimit) || 200000;
    var ADDRESS_LIMIT = Number(form.dataset.addressLimit) || 50000;
    var TDS_LIMIT = Number(form.dataset.tds) || 200000;
    var PURITIES = {};
    try { PURITIES = JSON.parse(form.dataset.purities || '{}'); } catch (e) {}
    var ORDER_ADVANCE = Number(form.dataset.advance) || 0;
    var PAN_RE = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
    var HUID_RE = /^[A-Z0-9]{6}$/;
    var cash = { room: Math.floor(CASH_LIMIT - 0.01), already: 0 };
    var tried = false;
    var pending = 0;

    function el(sel, root) { return (root || form).querySelector(sel); }
    function all(sel, root) { return Array.prototype.slice.call((root || form).querySelectorAll(sel)); }
    function field(name) { return el('[name="' + name + '"]'); }
    function val(name) { var f = field(name); return f ? f.value : ''; }
    function num(v) { var n = parseFloat(String(v == null ? '' : v).replace(/,/g, '')); return isFinite(n) ? n : 0; }
    function r2(n) { return Math.round((n + Number.EPSILON) * 100) / 100; }
    function inr(n, dp) { dp = dp == null ? 2 : dp; return '₹' + Number(n).toLocaleString('en-IN', { minimumFractionDigits: dp, maximumFractionDigits: dp }); }
    function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
    function toast(type, text) { if (window.portalToast) window.portalToast(type, text); }

    function rateOf(metal) { return metal === 'Gold' ? num(val('goldRate')) : (metal === 'Silver' ? num(val('silverRate')) : 0); }
    function interstate() {
        if (!isBill) return false;
        var sel = field('placeOfSupply');
        var o = sel && sel.options[sel.selectedIndex];
        return !!(o && o.dataset.code && o.dataset.code !== STATE);
    }
    function omTotal() { return all('[name="oldMetalIds[]"]:checked').reduce(function (a, x) { return a + num(x.dataset.amount); }, 0); }
    function payRows() {
        return [0, 1].map(function (i) { return { mode: val('payments[' + i + '][mode]') || 'Cash', amount: num(val('payments[' + i + '][amount]')) }; });
    }
    function rows() { return all('#items .item-row'); }
    function rf(row, name) { return el('[data-f="' + name + '"]', row); }
    function rv(row, name) { var f = rf(row, name); return f ? f.value : ''; }

    // ── one row -> an item for the engine, plus what is wrong with it ──
    function build(row) {
        var name = rv(row, 'particulars').trim();
        var net = rv(row, 'netWt').trim();
        var metal = rv(row, 'metalType') || 'Gold';
        var it = {
            particulars: name, metalType: metal, purity: rv(row, 'purity'), netWt: net, grossWt: rv(row, 'grossWt'), rate: rv(row, 'rate'), makingCharge: rv(row, 'makingCharge'),
            hsnCode: rv(row, 'hsnCode'), taxableOverride: rv(row, 'taxableOverride'), certification: rv(row, 'certification'), huid: rv(row, 'huid').toUpperCase(),
            hallmarkCharge: rv(row, 'hallmarkCharge'), productCode: rv(row, 'productCode'), itemId: rv(row, 'itemId')
        };
        if (num(rv(row, 'stoneAmount')) > 0 || num(rv(row, 'stoneWt')) > 0) {
            it.extras = [{ kind: 'Stone', name: rv(row, 'stoneName'), weight: num(rv(row, 'stoneWt')), amount: num(rv(row, 'stoneAmount')) }];
        }
        var active = name !== '' || net !== '' || num(rv(row, 'grossWt')) > 0 || num(rv(row, 'makingCharge')) > 0;
        return { row: row, item: it, active: active };
    }
    function itemProblems(b) {
        var out = [], it = b.item, row = b.row;
        function bad(fieldName, msg) { out.push({ el: rf(row, fieldName), msg: msg, row: row }); }
        if (!it.particulars) bad('particulars', 'Enter what is being sold');
        if (it.metalType !== 'Other' && !it.purity) bad('purity', 'Choose the purity');
        var net = num(it.netWt), gross = num(it.grossWt);
        if (!(net > 0)) bad('netWt', 'Net weight must be more than 0');
        else if (gross > 0 && net > gross + 0.0005) bad('netWt', 'Net weight cannot be more than gross weight');
        var rate = it.rate !== '' ? num(it.rate) : rateOf(it.metalType);
        if (!(rate > 0)) bad('rate', 'Enter the ' + it.metalType.toLowerCase() + ' rate');
        if (it.certification === 'huid' && !HUID_RE.test(it.huid)) bad('huid', 'HUID must be 6 letters or digits');
        if (String(it.taxableOverride).trim() !== '') {
            var to = num(it.taxableOverride), metalVal = r2(net * rate);
            if (!(to > 0)) bad('taxable', 'Taxable amount must be more than 0');
            else if (Math.round(to * 100) < Math.round(metalVal * 100)) bad('taxable', 'Taxable amount cannot be below the metal value (' + inr(metalVal) + ')');
        }
        return out;
    }

    // ── everything at once ──
    var last = {};
    function recompute() {
        pending = 0;
        var builds = rows().map(build);
        var actives = builds.filter(function (b) { return b.active; });
        var issues = [];
        var itemIssues = [];
        actives.forEach(function (b) { itemIssues = itemIssues.concat(itemProblems(b)); });
        var allRows = rows();

        var items = actives.map(function (b) { return b.item; });
        var inter = interstate();
        var gold = num(val('goldRate')), silver = num(val('silverRate'));
        var discount = num(val('discount'));
        var extra = num(val('additionalCharges'));
        var pays = isBill ? payRows() : [];
        var credit = isBill ? omTotal() + ORDER_ADVANCE : 0;
        var received = pays.reduce(function (a, p) { return a + p.amount; }, 0);
        var calc = null, t0 = null;
        if (items.length && !itemIssues.length) {
            var base = { items: items, goldRate: gold, silverRate: silver, interstate: inter, additionalCharges: extra };
            t0 = C.computeInvoice(Object.assign({ discount: 0, paidAmount: 0 }, base));
            calc = C.computeInvoice(Object.assign({ discount: discount, paidAmount: received + credit }, base));
        }
        ensureBlankRow(builds);
        last = { calc: calc, t0: t0, received: received, credit: credit, pays: pays };

        // line amounts
        actives.forEach(function (b) {
            var out = el('.line-amt', b.row);
            var single = null;
            if (!itemProblems(b).length) single = C.computeInvoice({ items: [b.item], goldRate: gold, silverRate: silver, interstate: inter, additionalCharges: 0, discount: 0, paidAmount: 0 });
            if (out) out.textContent = single && single.ok ? inr(single.totalPayableAmount === undefined ? 0 : single.items[0].total) : '–';
            // the taxable box shows what the engine works out until someone types their own amount
            showTaxable(b.row, single && single.ok ? single.items[0].taxable_amount : null);
        });
        rows().forEach(function (r) {
            if (!actives.some(function (b) { return b.row === r; })) { var o = el('.line-amt', r); if (o) o.textContent = '–'; showTaxable(r, null); }
            var m = rv(r, 'metalType');
            var rf2 = rf(r, 'rate');
            if (rf2) rf2.placeholder = rateOf(m) > 0 ? rateOf(m).toFixed(2) : 'rate';
            r.dataset.metal = m;
            var cert = rv(r, 'certification'), hi = rf(r, 'huid'), hf = rf(r, 'hallmarkCharge');
            r.classList.toggle('has-cert', cert !== '');
            if (hi) hi.disabled = cert !== 'huid';
            if (hf) hf.disabled = cert === '';
        });

        // ── checks (same rules as the app; the server checks them again) ──
        var payable = calc && calc.ok ? calc.totalPayableAmount : 0;
        if (!items.length) issues.push({ msg: 'Add at least one item' });
        itemIssues.forEach(function (p) { issues.push({ el: p.el, msg: 'Item ' + (allRows.indexOf(p.row) + 1) + ': ' + p.msg }); });
        var cid = val('customerId'), cname = val('customerName').trim();
        if (!cid && cname.length < 2) issues.push({ el: field('customerName'), msg: "Choose a customer, or enter the buyer's name" });
        var digits = val('customerMobile').replace(/\D/g, '');
        if (digits.length > 10 && /^(91|0)/.test(digits)) digits = digits.slice(-10);
        if (digits && digits.length !== 10) issues.push({ el: field('customerMobile'), msg: 'Mobile number must be 10 digits' });
        if (calc && !calc.ok) {
            var dEl = /discount/i.test(calc.error) ? field('discount') : null;
            issues.push({ el: dEl, msg: calc.error });
        }
        var tdsOn = calc && calc.ok && calc.tdsApplicable;
        if (isBill) {
            var bd = val('invoiceDate'), todayStr = (field('invoiceDate') || {}).max || '';
            if (!bd) issues.push({ el: field('invoiceDate'), msg: 'Choose the bill date' });
            else if (todayStr && bd > todayStr) issues.push({ el: field('invoiceDate'), msg: 'Bill date cannot be a future day' });
            var pan = val('customerPan').trim().toUpperCase();
            if (pan && !PAN_RE.test(pan)) issues.push({ el: field('customerPan'), msg: 'PAN must look like ABCDE1234F (5 letters, 4 digits, 1 letter)' });
            else if (tdsOn && !pan) issues.push({ el: field('customerPan'), msg: 'Enter the customer PAN: the bill is above ' + inr(TDS_LIMIT, 0) });
            var needAddr = payable >= ADDRESS_LIMIT;
            if (needAddr && val('customerAddress').trim().length < 5) issues.push({ el: field('customerAddress'), msg: "Enter the buyer's address: needed on a bill of " + inr(ADDRESS_LIMIT, 0) + ' or more' });
            var cashNow = pays.reduce(function (a, p) { return a + (p.mode === 'Cash' ? p.amount : 0); }, 0);
            if (cashNow > cash.room + 0.001) {
                issues.push({ el: field('payments[0][amount]'), msg: cash.room > 0
                    ? 'Cash limit (s.269ST): at most ' + inr(cash.room, 0) + ' can be taken in cash from this customer today. Take the rest by Card, Online or Cheque.'
                    : 'Cash limit (s.269ST): no more cash can be taken from this customer today. Use Card, Online or Cheque.' });
            }
            if (calc && calc.ok) {
                if (!cid && (calc.dueAmount > 0 || calc.advanceAmount > 0)) issues.push({ el: field('payments[0][amount]'), msg: 'A walk-in bill must be paid in full. Pick a saved customer to keep a due balance.' });
                if (calc.advanceAmount > 0 && cid && received + credit > payable + 0.005) { /* an advance on a saved customer is allowed */ }
            }
        }
        last.issues = issues;

        if (syncPaid(payable) && !recompute.again) { recompute.again = true; recompute(); recompute.again = false; return; }
        renderTotals(calc, t0, issues, payable);
        renderHints(t0, calc);
        syncFinal(payable);
        markFields(issues);
    }

    function renderTotals(c, t0, issues, payable) {
        var box = el('#totals');
        if (!c || !c.ok) {
            box.innerHTML = '<p class="muted">' + (c && !c.ok ? esc(c.error) : 'Add an item to see the total.') + '</p>';
        } else {
            var g = c.gstSummary, h = '<div class="kv">';
            if (c.discountGiven > 0) h += '<div class="kv-row"><span>Price before discount</span><strong>' + inr(c.billBeforeDiscount) + '</strong></div><div class="kv-row"><span>Discount</span><strong class="neg">− ' + inr(c.discountGiven) + '</strong></div>';
            h += '<div class="kv-row"><span>Taxable value</span><strong>' + inr(g.total_taxable_amount) + '</strong></div>';
            if (c.gstType === 'IGST') h += '<div class="kv-row"><span>IGST 3%</span><strong>' + inr(g.total_igst || 0) + '</strong></div>';
            else h += '<div class="kv-row"><span>CGST 1.5%</span><strong>' + inr(g.total_cgst) + '</strong></div><div class="kv-row"><span>SGST 1.5%</span><strong>' + inr(g.total_sgst) + '</strong></div>';
            if (c.hallmarkTotal > 0) h += '<div class="kv-row"><span>Hallmark / HUID fee (no GST)</span><strong>' + inr(c.hallmarkTotal) + '</strong></div>';
            if (c.additionalCharges > 0) h += '<div class="kv-row"><span>Extra charge</span><strong>' + inr(c.additionalCharges) + '</strong></div>';
            h += '<div class="kv-row"><span>Round off</span><strong>' + (c.roundOff >= 0 ? '' : '− ') + inr(Math.abs(c.roundOff)) + '</strong></div>';
            h += '<div class="kv-row total"><span>Bill total</span><strong>' + inr(c.totalPayableAmount, 0) + '</strong></div>';
            if (c.totalPayableAmount) h += '<div class="words">' + esc((function () { var w = C.amountInWords ? C.amountInWords(c.totalPayableAmount) : ''; return w && typeof w === 'object' ? (w.en || '') : w; })()) + '</div>';
            if (isBill) {
                var credit = last.credit || 0;
                if (credit > 0) h += '<div class="kv-row"><span>Old metal / order advance</span><strong class="pos">− ' + inr(credit) + '</strong></div>';
                h += '<div class="kv-row"><span>Received now</span><strong>' + inr(last.received) + '</strong></div>';
                if (c.dueAmount > 0) h += '<div class="kv-row due"><span>Balance due</span><strong class="neg">' + inr(c.dueAmount) + '</strong></div>';
                else if (c.advanceAmount > 0) h += '<div class="kv-row"><span>Advance (extra paid)</span><strong>' + inr(c.advanceAmount) + '</strong></div>';
                else h += '<div class="kv-row"><span>Balance</span><strong class="pos">Nil</strong></div>';
            }
            if (c.tdsApplicable) h += '<p class="notice notice-info">Bill above ' + inr(TDS_LIMIT, 0) + ': TDS ' + c.tdsRate + '% = ' + inr(c.tdsAmount) + '. PAN is required.</p>';
            box.innerHTML = h + '</div>';
        }
        var bt = el('#bar-total'), br = el('#bar-recv'), bd = el('#bar-due'), bm = el('#bar-msg');
        if (bt) bt.textContent = c && c.ok ? inr(c.totalPayableAmount, 0) : '₹0';
        if (br) br.textContent = c && c.ok ? inr(last.received, 0) : '₹0';
        if (bd) { var due = c && c.ok ? c.dueAmount : 0; bd.textContent = inr(due, 0); bd.className = due > 0 ? 'neg' : ''; }
        if (bm) {
            bm.className = 'bar-msg ' + (issues.length ? 'is-warn' : (c && c.ok ? 'is-ok' : ''));
            bm.textContent = issues.length ? '⚠ ' + issues.length + ' to fix: ' + issues[0].msg : (c && c.ok ? '✓ Ready to save' : 'Add an item to start.');
            bm.title = issues.map(function (i) { return i.msg; }).join(' | ');
        }
        var list = el('#issues');
        if (!list) return;
        if (!issues.length) { list.hidden = true; list.innerHTML = ''; }
        else {
            list.hidden = false;
            list.innerHTML = '<strong>To fix before saving</strong><ul>' + issues.slice(0, 6).map(function (i) { return '<li>' + esc(i.msg) + '</li>'; }).join('') + '</ul>';
        }
    }

    function setTip(id, text) {
        var t = el('#' + id);
        if (!t) return;
        t.dataset.tip0 = text;
        if (!t.closest('.need')) t.dataset.tip = text;
    }
    function renderHints(t0, c) {
        if (t0 && t0.ok) {
            setTip('tip-disc', t0.maxDiscount > 0
                ? 'Most discount possible: ' + inr(t0.maxDiscount, 0) + '. It comes off the making charge; the metal, stones and hallmark are never discounted.'
                : 'No discount is possible: there is no making charge above the metal value.');
        }
        if (isBill) {
            setTip('tip-pay', cash.already > 0
                ? 'Cash already taken today from this customer: ' + inr(cash.already, 0) + '. At most ' + inr(cash.room, 0) + ' more in cash (s.269ST).'
                : 'Cash of ' + inr(CASH_LIMIT, 0) + ' or more from one customer in a day is not allowed (s.269ST). At most ' + inr(cash.room, 0) + ' today.');
        }
    }

    // paid amount follows the bill until someone types it (as in the app)
    function syncPaid(payable) {
        if (!isBill) return false;
        var p0 = field('payments[0][amount]'), p1 = field('payments[1][amount]');
        if (!p0 || p0.dataset.touched === '1' || document.activeElement === p0) return false;
        var need = payable - omTotal() - ORDER_ADVANCE;
        var fine = omTotal() + ORDER_ADVANCE > 0;
        var fmt = function (v) { return v <= 0 ? '' : (fine ? String(r2(v)) : String(Math.round(v))); };
        var p1Free = !p1 || p1.dataset.touched !== '1';
        var next0, next1 = null;
        if (p1Free && val('payments[0][mode]') === 'Cash' && need > cash.room && need > 0) {
            // more cash than the law allows from one person in a day: the rest is put on the second payment automatically
            next0 = fmt(cash.room);
            next1 = fmt(need - cash.room);
            var m1 = field('payments[1][mode]');
            if (m1 && m1.value === 'Cash') m1.value = 'Online';
        } else {
            next0 = fmt(need - (p1Free ? 0 : num(p1.value)));
            if (p1Free && p1) next1 = '';
        }
        var changed = next0 !== p0.value;
        p0.value = next0;
        if (next1 !== null && p1 && p1.value !== next1) { p1.value = next1; changed = true; }
        return changed;
    }
    function syncFinal(payable) {
        var f = el('#final-amount');
        if (f && document.activeElement !== f) f.value = payable ? String(payable) : '';
    }
    function markFields(issues) {
        all('.bad').forEach(function (e) { e.classList.remove('bad'); delete e.dataset.msg; });
        all('.need').forEach(function (l) { l.classList.remove('need'); var t = el('.tip', l); if (t && t.dataset.tip0) t.dataset.tip = t.dataset.tip0; });
        issues.forEach(function (i) {
            if (!i.el || !(tried || i.el.dataset.blur === '1')) return;
            i.el.classList.add('bad');
            if (i.el.dataset.msg == null) i.el.dataset.msg = i.msg;
            var lab = i.el.closest('.cf');
            var tip = lab && el('.tip', lab);
            if (tip && lab.querySelector('span') && lab.querySelector('span').contains(tip)) { lab.classList.add('need'); tip.dataset.tip = i.msg; }
        });
    }

    // a red field with no "?" of its own explains itself in a small pop-up when pointed at or focused
    var tipbox = document.createElement('div');
    tipbox.className = 'tipbox';
    tipbox.hidden = true;
    document.body.appendChild(tipbox);
    function showBox(e) {
        var t = e.target;
        if (!t.classList || !t.classList.contains('bad') || !t.dataset.msg) return;
        var lab = t.closest('.cf');
        if (lab && lab.classList.contains('need')) return;
        var r = t.getBoundingClientRect();
        tipbox.textContent = t.dataset.msg;
        tipbox.hidden = false;
        tipbox.style.left = Math.max(6, Math.min(window.innerWidth - 260, r.left)) + 'px';
        tipbox.style.top = (window.scrollY + r.top - tipbox.offsetHeight - 6) + 'px';
    }
    function hideBox() { tipbox.hidden = true; }
    form.addEventListener('mouseover', showBox);
    form.addEventListener('focusin', showBox);
    form.addEventListener('mouseout', hideBox);
    form.addEventListener('focusout', hideBox);

    // ── discount helpers ──
    function onFinalTyped(e) {
        var t0 = last.t0;
        if (!t0 || !t0.ok) return;
        var f = num(e.target.value);
        var d = f > 0 ? t0.billBeforeDiscount - f : 0;
        if (d > t0.maxDiscount) d = t0.maxDiscount;
        field('discount').value = d > 0 ? String(Math.round(d)) : '';
        schedule();
    }
    function roundTo(m) {
        var t0 = last.t0;
        if (!t0 || !t0.ok) { toast('info', 'Add an item first'); return; }
        var before = t0.billBeforeDiscount, lowest = before - t0.maxDiscount;
        var target = Math.floor(before / m) * m;
        if (target < lowest) target = Math.ceil(lowest / m) * m;
        if (target <= 0 || target >= before) { toast('info', t0.maxDiscount > 0 ? 'Cannot round further: the lowest price is ' + inr(lowest, 0) : 'No discount is possible on this bill'); return; }
        field('discount').value = String(Math.round(before - target));
        schedule();
    }
    function quickPay(frac) {
        var c = last.calc;
        if (!c || !c.ok) return;
        var p0 = field('payments[0][amount]');
        var rest = c.totalPayableAmount - payRows()[1].amount - omTotal() - ORDER_ADVANCE;
        if (frac === 1) { p0.dataset.touched = ''; }
        else { p0.dataset.touched = '1'; p0.value = frac === 0 ? '' : String(Math.max(0, Math.round(rest * frac))); }
        schedule();
    }

    // ── rows ──
    function setPurities(row, keepUnknown) {
        var metal = rv(row, 'metalType'), sel = rf(row, 'purity'), list = PURITIES[metal] || [];
        var cur = sel.value, chosen = '';
        list.forEach(function (p) { if (p.toLowerCase() === cur.toLowerCase()) chosen = p; });
        var html = '<option value="">–</option>' + list.map(function (p) { return '<option' + (p === chosen ? ' selected' : '') + '>' + esc(p) + '</option>'; }).join('');
        // a purity the shop wrote differently (916, 22k...) stays as typed instead of being lost
        if (!chosen && cur && (keepUnknown || metal === 'Other')) html += '<option selected>' + esc(cur) + '</option>';
        sel.innerHTML = html;
    }
    function dropEmptyRows() {
        var all = rows();
        if (all.length < 2) return;
        all.forEach(function (r) {
            if (!build(r).active && !rv(r, 'productCode') && rows().length > 1) r.parentNode.removeChild(r);
        });
    }
    function fmtOnBlur(inp) {
        var dp = inp.dataset.dp;
        if (dp == null || inp.value.trim() === '') return;
        var n = parseFloat(inp.value.replace(/,/g, ''));
        if (isFinite(n)) inp.value = n.toFixed(Number(dp));
    }
    function autoNet(row) {
        var net = rf(row, 'netWt');
        if (net.dataset.typed === '1') return;
        var g = num(rv(row, 'grossWt')), st = num(rv(row, 'stoneWt'));
        net.value = g > 0 ? Math.max(0, Math.round((g - st) * 1000) / 1000).toFixed(3) : '';
    }
    function dedupe() {
        var seen = {};
        rows().forEach(function (r) {
            var code = rv(r, 'productCode');
            if (!code) return;
            if (seen[code]) { r.parentNode.removeChild(r); toast('error', code + ' is already on this bill'); } else seen[code] = 1;
        });
    }

    // a new empty row appears by itself when the last one is being filled, so nobody has to press "Add item"
    var adding = false;
    function ensureBlankRow(builds) {
        if (adding || !builds.length) return;
        var lastB = builds[builds.length - 1];
        if (lastB.active && window.htmx) {
            adding = true;
            window.htmx.ajax('GET', '/billing/row', { target: '#items', swap: 'beforeend' }).then(function () { adding = false; }, function () { adding = false; });
        }
    }

    // a 10-digit mobile that belongs to a saved customer fills the name, address, PAN and state
    var mobTimer = null;
    function lookupMobile() {
        window.clearTimeout(mobTimer);
        mobTimer = window.setTimeout(function () {
            var m = val('customerMobile').replace(/\D/g, '');
            if (m.length < 10 || val('customerId')) return;
            fetch('/billing/customer-by-mobile?mobile=' + encodeURIComponent(m), { credentials: 'same-origin' }).then(function (r) { return r.json(); }).then(function (d) {
                if (!d.found || val('customerId')) return;
                field('customerId').value = d.id;
                field('customerName').value = d.name || val('customerName');
                if (!val('customerAddress') && d.address) field('customerAddress').value = d.address;
                if (!val('customerPan') && d.pan) field('customerPan').value = d.pan;
                var sel = field('placeOfSupply');
                if (sel && d.place) for (var i = 0; i < sel.options.length; i++) if (sel.options[i].value === d.place) sel.selectedIndex = i;
                toast('info', 'Saved customer found: ' + (d.name || '') + (d.due > 0 ? ' (owes ' + inr(d.due, 0) + ')' : ''));
                form.dispatchEvent(new CustomEvent('customer-changed'));
            }).catch(function () {});
        }, 350);
    }

    // the taxable column: the calculated amount (grey) until it is typed over (amber, with a reset button)
    function showTaxable(row, auto) {
        var tx = rf(row, 'taxable'), hid = rf(row, 'taxableOverride'), rst = el('[data-tx-reset]', row);
        if (!tx || !hid) return;
        var ov = hid.value.trim() !== '';
        tx.classList.toggle('is-ov', ov);
        if (rst) rst.hidden = !ov;
        if (!ov && document.activeElement !== tx) tx.value = auto == null ? '' : auto.toFixed(2);
    }

    function schedule() {
        if (pending) return;
        pending = window.setTimeout(recompute, 0);
    }

    // ── events ──
    form.addEventListener('input', function (e) {
        var t = e.target;
        if (t.dataset && t.dataset.upper != null) { var s = t.selectionStart; t.value = t.value.toUpperCase(); try { t.setSelectionRange(s, s); } catch (x) {} }
        var row = t.closest && t.closest('.item-row');
        if (row) {
            var f = t.dataset.f;
            if (f === 'taxable') { rf(row, 'taxableOverride').value = t.value.trim(); }
            if (f === 'netWt') t.dataset.typed = t.value.trim() === '' ? '' : '1';
            if (f === 'grossWt' || f === 'stoneWt') autoNet(row);
        }
        if (t.id === 'final-amount') { onFinalTyped(e); return; }
        if (t.name === 'customerMobile') lookupMobile();
        if (t.name === 'customerName' && t.closest('.pos-cust')) { /* typing a name again means: not a saved customer unless one is picked */ }
        if (t.dataset && (t.dataset.pay === '0' || t.dataset.pay === '1')) t.dataset.touched = t.value.trim() === '' && t.dataset.pay === '1' ? '' : '1';
        schedule();
    });
    form.addEventListener('change', function (e) {
        var t = e.target, row = t.closest && t.closest('.item-row');
        if (row && t.dataset.f === 'metalType') { setPurities(row, false); }
        if (row && t.dataset.f === 'certification') {
            if (t.value !== 'huid') rf(row, 'huid').value = '';
            if (t.value === '') rf(row, 'hallmarkCharge').value = '';
            if (t.value === 'huid') window.setTimeout(function () { rf(row, 'huid').focus(); }, 0);
        }
        if (t.name === 'customerMobile' || t.name === 'customerName') loadCash();
        schedule();
    });
    form.addEventListener('focusout', function (e) {
        var t = e.target;
        if (t.dataset) { t.dataset.blur = '1'; fmtOnBlur(t); }
        schedule();
    });
    form.addEventListener('customer-changed', function () { loadCash(); schedule(); });
    form.addEventListener('click', function (e) {
        var tr = e.target.closest('[data-tx-reset]');
        if (tr) { var rw = tr.closest('.item-row'); rf(rw, 'taxableOverride').value = ''; rf(rw, 'taxable').value = ''; schedule(); return; }
        var r = e.target.closest('[data-round]'), q = e.target.closest('[data-pay-frac]');
        if (r) roundTo(Number(r.dataset.round));
        if (q) quickPay(Number(q.dataset.payFrac));
    });
    document.body.addEventListener('htmx:afterSettle', function (e) {
        var t = e.detail && e.detail.target;
        if (t && t.id === 'items') { dedupe(); if (/stock-row/.test(((e.detail && e.detail.pathInfo) || {}).requestPath || '')) dropEmptyRows(); rows().forEach(function (r) { setPurities(r, true); }); schedule(); }
        if (t && t.id === 'old-metal') schedule();
    });
    form.addEventListener('submit', function (e) {
        recompute();
        var issues = last.issues || [];
        if (issues.length) {
            e.preventDefault();
            tried = true;
            markFields(issues);
            toast('error', issues[0].msg);
            var first = issues.filter(function (i) { return i.el; })[0];
            if (first) { first.el.scrollIntoView({ block: 'center', behavior: 'smooth' }); try { first.el.focus({ preventScroll: true }); } catch (x) {} }
            return;
        }
        var b = el('#save-btn');
        if (b) { b.disabled = true; b.textContent = 'Saving…'; }
    });

    // how much cash may still be taken today from this person
    var cashTimer = null;
    function loadCash() {
        if (!isBill) return;
        window.clearTimeout(cashTimer);
        cashTimer = window.setTimeout(function () {
            var q = 'customerId=' + encodeURIComponent(val('customerId')) + '&mobile=' + encodeURIComponent(val('customerMobile').replace(/\D/g, '').slice(-10));
            fetch('/billing/cash-room?' + q, { credentials: 'same-origin' }).then(function (r) { return r.json(); }).then(function (d) {
                cash.room = Math.max(0, Number(d.room)); cash.already = Number(d.alreadyToday) || 0;
                var h = el('#cash-hint');
                if (h) h.textContent = cash.already > 0 ? 'Cash taken today from this customer: ' + inr(cash.already, 0) + ' · can still take ' + inr(cash.room, 0) : '';
                schedule();
            }).catch(function () {});
        }, 300);
    }

    // start
    rows().forEach(function (r) { setPurities(r, true); });
    loadCash();
    recompute();
})();
