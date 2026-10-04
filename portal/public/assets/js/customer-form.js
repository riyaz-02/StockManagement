/* The customer form (pop-up or page): several phone numbers, a live "already saved" check, Bengali that fills itself, a
   "referred by" search. Plain JavaScript, all events on the document, so it also works for a form that arrives later (htmx). */
(function () {
    'use strict';
    var MAX_NUMBERS = 6;

    function csrf() { var m = document.querySelector('meta[name="csrf"]'); return m ? m.content : ''; }
    function esc(t) { var d = document.createElement('div'); d.textContent = t == null ? '' : String(t); return d.innerHTML; }
    function digits(v) { var d = String(v || '').replace(/\D/g, ''); return d.length > 10 ? d.slice(-10) : d; }
    function debounce(fn, ms) { var t; return function () { var a = arguments, c = this; clearTimeout(t); t = setTimeout(function () { fn.apply(c, a); }, ms); }; }
    function formOf(el) { return el && el.closest ? el.closest('[data-cform]') : null; }
    function q(form, sel) { return form.querySelector(sel); }
    function title(s) { return s.replace(/(^|[\s.\-(\/])([a-zà-ÿ])/g, function (m, a, b) { return a + b.toUpperCase(); }); }

    // ── phone numbers ──────────────────────────────────────────────────────────────────────────
    function numberInputs(form) { return Array.prototype.slice.call(form.querySelectorAll('[data-cf-number]')); }

    function paintNumber(input) {
        var n = digits(input.value);
        input.classList.toggle('is-ok', n.length === 10);
        input.classList.toggle('is-part', n.length > 0 && n.length < 10);
        // the same number twice in this form
        var form = formOf(input);
        var again = false;
        if (n.length === 10) {
            numberInputs(form).forEach(function (o) { if (o !== input && digits(o.value) === n) { again = true; } });
        }
        input.classList.toggle('is-bad', again);
        input.title = again ? 'This number is already entered above' : '';
    }

    var seq = 0;
    var checkNumbers = debounce(function (form) {
        var nums = numberInputs(form).map(function (i) { return digits(i.value); }).filter(function (n) { return n.length >= 8; });
        var box = q(form, '[data-cf-dupes]');
        if (!nums.length) { box.hidden = true; box.innerHTML = ''; form.dataset.dupe = ''; return; }
        var mine = ++seq;
        var exclude = form.getAttribute('data-exclude') || '';
        Promise.all(nums.map(function (n) {
            return fetch('/directory/lookup?q=' + encodeURIComponent(n) + (exclude ? '&exclude=' + encodeURIComponent(exclude) : ''), { credentials: 'same-origin', headers: { 'Accept': 'application/json' } })
                .then(function (r) { return r.ok ? r.json() : { results: [] }; }).catch(function () { return { results: [] }; });
        })).then(function (all) {
            if (mine !== seq) { return; }
            var seen = {}, rows = [], exact = false;
            all.forEach(function (a) { (a.results || []).forEach(function (c) { if (!seen[c.id]) { seen[c.id] = 1; rows.push(c); if (c.exact) { exact = true; } } }); });
            form.dataset.dupe = exact ? '1' : '';
            if (!rows.length) { box.hidden = true; box.innerHTML = ''; return; }
            box.hidden = false;
            box.className = 'cf-dupes ' + (exact ? 'is-exact' : 'is-similar');
            box.innerHTML = '<strong>' + (exact ? 'This number is already saved' : 'Similar numbers are already saved') + '</strong>' +
                rows.slice(0, 4).map(function (c) {
                    return '<a class="cf-dupe" href="/directory/customers/' + esc(c.id) + '" target="_blank" rel="noopener">' +
                        '<b>' + esc(c.name) + '</b>' + (c.nameBn ? ' <span>' + esc(c.nameBn) + '</span>' : '') +
                        (c.serialNo ? ' <em>#' + esc(c.serialNo) + '</em>' : '') +
                        '<small>' + esc((c.matchedNumber || (c.phones || [])[0] || '')) + (c.address ? ' · ' + esc(c.address) : '') + '</small></a>';
                }).join('') +
                (exact ? '<label class="check"><input type="checkbox" data-cf-anyway> <span>Add anyway (a second customer with the same number)</span></label>' : '');
        });
    }, 300);

    document.addEventListener('input', function (e) {
        var t = e.target;
        if (!t || !t.matches) { return; }
        var form = formOf(t);
        if (!form) { return; }
        if (t.matches('[data-cf-number]')) {
            // only digits; a pasted "+91 98300 12345" keeps the last 10
            var all = t.value.replace(/\D/g, '');
            if (all.length > 10) { all = /^(91|0)/.test(all) && all.length <= 13 ? all.slice(-10) : all.slice(0, 10); }
            t.value = all;
            numberInputs(form).forEach(paintNumber);
            checkNumbers(form);
        } else if (t.matches('[data-cf-name]')) {
            translateLater(form, 'name');
        } else if (t.matches('[data-cf-address]')) {
            translateLater(form, 'address');
        } else if (t.matches('[data-cf-name-bn]')) {
            t.dataset.touched = '1';
        } else if (t.matches('[data-cf-address-bn]')) {
            t.dataset.touched = '1';
        } else if (t.matches('[data-cf-ref-input]')) {
            refSearch(form);
        }
    });

    document.addEventListener('focusout', function (e) {
        var t = e.target;
        if (!t || !t.matches) { return; }
        if (t.matches('[data-cf-name], [data-cf-address]')) { t.value = title(t.value.replace(/\s+/g, ' ').trimStart()); }
    });

    document.addEventListener('click', function (e) {
        var t = e.target.closest ? e.target.closest('button, [data-cf-add]') : null;
        if (!t) { return; }
        var form = formOf(t);
        if (!form) { return; }
        if (t.matches('[data-cf-add]')) {
            var list = q(form, '[data-cf-numbers]');
            var rows = list.querySelectorAll('[data-cf-num]');
            if (rows.length >= MAX_NUMBERS) { return; }
            var tpl = rows[rows.length - 1].cloneNode(true);
            if (rows.length === 1) {
                // the first row has no kind selector: build one for the new rows
                var badge = tpl.querySelector('.cf-badge');
                var sel = document.createElement('select');
                sel.name = 'label[]';
                sel.setAttribute('aria-label', 'Kind of number');
                [['mobile', 'Mobile'], ['home', 'Home'], ['work', 'Work'], ['other', 'Other'], ['whatsapp', 'WhatsApp']].forEach(function (o) { var op = document.createElement('option'); op.value = o[0]; op.textContent = o[1]; sel.appendChild(op); });
                tpl.replaceChild(sel, badge);
                var rm = document.createElement('button');
                rm.type = 'button'; rm.className = 'icon-btn'; rm.setAttribute('data-cf-remove', ''); rm.setAttribute('aria-label', 'Remove this number'); rm.textContent = '×';
                tpl.appendChild(rm);
            }
            var inp = tpl.querySelector('[data-cf-number]');
            inp.value = ''; inp.placeholder = 'Another number'; inp.removeAttribute('autofocus'); inp.classList.remove('is-ok', 'is-part', 'is-bad');
            list.insertBefore(tpl, q(form, '[data-cf-dupes]'));
            inp.focus();
            q(form, '[data-cf-add]').hidden = list.querySelectorAll('[data-cf-num]').length >= MAX_NUMBERS;
        } else if (t.matches('[data-cf-date-add]')) {
            var tplEl = q(form, '[data-cf-date-tpl]');
            var rowsAt = q(form, '[data-cf-dates]');
            var added = tplEl.content.firstElementChild.cloneNode(true);
            rowsAt.insertBefore(added, t);
            var count = rowsAt.querySelectorAll('[data-cf-date]').length;
            // the first row asks for a birthday, the next for an anniversary: what shops enter most
            var occ = added.querySelector('input[name="dateOccasion[]"]');
            if (count === 1) { occ.value = 'Birthday'; added.querySelector('input[type="date"]').focus(); } else { occ.focus(); }
            t.hidden = count >= 12;
        } else if (t.matches('[data-cf-date-remove]')) {
            var dr = t.closest('[data-cf-date]');
            if (dr) { dr.remove(); }
            q(form, '[data-cf-date-add]').hidden = false;
        } else if (t.matches('[data-cf-remove]')) {
            var row = t.closest('[data-cf-num]');
            if (row) { row.remove(); }
            q(form, '[data-cf-add]').hidden = false;
            numberInputs(form).forEach(paintNumber);
            checkNumbers(form);
        } else if (t.matches('[data-cf-retranslate]')) {
            translateNow(form, t.getAttribute('data-cf-retranslate'), true);
        } else if (t.matches('[data-cf-ref-clear]')) {
            q(form, '[data-cf-ref-id]').value = '';
            q(form, '[data-cf-ref-chip]').hidden = true;
            q(form, '[data-cf-ref-input]').value = '';
            q(form, '[data-cf-ref-input]').closest('.field').hidden = false;
        } else if (t.matches('[data-cf-pick]')) {
            q(form, '[data-cf-ref-id]').value = t.getAttribute('data-cf-pick');
            q(form, '[data-cf-ref-label]').textContent = t.getAttribute('data-label');
            q(form, '[data-cf-ref-chip]').hidden = false;
            q(form, '[data-cf-ref-input]').value = '';
            q(form, '[data-cf-ref-input]').closest('.field').hidden = true;
            var res = q(form, '[data-cf-ref-results]'); res.hidden = true; res.innerHTML = '';
        }
    });

    document.addEventListener('change', function (e) {
        var t = e.target;
        if (t && t.matches && t.matches('[data-cf-anyway]')) {
            var form = formOf(t);
            q(form, '[data-cf-force]').value = t.checked ? '1' : '';
        }
    });

    // a number that is already saved must be confirmed ("Add anyway") before the form is sent
    document.addEventListener('submit', function (e) {
        var form = e.target;
        if (!form.matches || !form.matches('[data-cform]')) { return; }
        var bad = numberInputs(form).some(function (i) { return i.classList.contains('is-bad'); });
        var first = numberInputs(form)[0];
        var msg = '';
        if (!first || digits(first.value).length !== 10) { msg = 'Enter the 10-digit mobile / WhatsApp number.'; first && first.focus(); }
        else if (bad) { msg = 'The same number is entered twice.'; }
        else if (form.dataset.dupe === '1' && !q(form, '[data-cf-force]').value) { msg = 'This number is already saved: tick "Add anyway" to save it again.'; }
        else if (Array.prototype.some.call(form.querySelectorAll('[data-cf-date]'), function (r) {
            var o = r.querySelector('input[name="dateOccasion[]"]').value.trim(), d = r.querySelector('input[type="date"]').value;
            return (o === '') !== (d === '');
        })) { msg = 'Each special date needs both the occasion and the date (or remove the row).'; }
        else if (!q(form, '[data-cf-name]').value.trim()) { msg = 'Enter the name.'; q(form, '[data-cf-name]').focus(); }
        if (msg) {
            e.preventDefault();
            e.stopPropagation();
            var box = q(form, '.cf-error') || (function () { var d = document.createElement('div'); d.className = 'notice notice-error cf-error'; d.setAttribute('role', 'alert'); form.insertBefore(d, q(form, '.cf-numbers')); return d; })();
            box.textContent = msg;
            return;
        }
        var btn = q(form, '[data-cf-save]');
        if (btn) { btn.disabled = true; btn.dataset.label = btn.textContent; btn.textContent = 'Saving...'; }
    }, true);

    // ── Bengali that fills itself ──────────────────────────────────────────────────────────────
    var fields = {
        name: { src: '[data-cf-name]', dst: '[data-cf-name-bn]' },
        address: { src: '[data-cf-address]', dst: '[data-cf-address-bn]' }
    };
    var timers = {};
    function translateLater(form, kind) {
        clearTimeout(timers[kind]);
        timers[kind] = setTimeout(function () { translateNow(form, kind, false); }, 700);
    }
    function translateNow(form, kind, force) {
        var f = fields[kind];
        var src = q(form, f.src), dst = q(form, f.dst);
        var text = src.value.trim();
        if (text.length < 2) { return; }
        // what the person typed in the Bengali box is left alone (until they press the translate button)
        if (!force && dst.value.trim() !== '' && dst.value !== dst.dataset.auto) { return; }
        dst.classList.add('is-working');
        var body = {}; body[kind] = text;
        fetch('/directory/translate', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', 'Accept': 'application/json', 'X-CSRF-Token': csrf() }, body: JSON.stringify(body) })
            .then(function (r) { return r.ok ? r.json() : { translations: {} }; })
            .then(function (j) {
                var v = (j.translations || {})[kind];
                if (v && src.value.trim() === text) { dst.value = v; dst.dataset.auto = v; dst.dataset.touched = ''; }
            })
            .catch(function () { /* the Bengali box simply stays for typing */ })
            .then(function () { dst.classList.remove('is-working'); });
    }

    // ── "referred by" ──────────────────────────────────────────────────────────────────────────
    var refSearch = debounce(function (form) {
        var input = q(form, '[data-cf-ref-input]');
        var res = q(form, '[data-cf-ref-results]');
        var term = input.value.trim();
        if (term.length < 2 && digits(term).length < 4) { res.hidden = true; res.innerHTML = ''; return; }
        var exclude = form.getAttribute('data-exclude') || '';
        fetch('/directory/lookup?q=' + encodeURIComponent(term) + (exclude ? '&exclude=' + encodeURIComponent(exclude) : ''), { credentials: 'same-origin', headers: { 'Accept': 'application/json' } })
            .then(function (r) { return r.ok ? r.json() : { results: [] }; })
            .then(function (j) {
                var rows = (j.results || []).slice(0, 5);
                if (!rows.length) { res.hidden = true; res.innerHTML = ''; return; }
                res.hidden = false;
                res.innerHTML = rows.map(function (c) {
                    var label = c.name + (c.code ? ' · ' + c.code : '');
                    return '<button type="button" class="cf-result" data-cf-pick="' + esc(c.id) + '" data-label="' + esc(label) + '"><b>' + esc(c.name) + '</b>' +
                        (c.serialNo ? ' <em>#' + esc(c.serialNo) + '</em>' : '') + '<small>' + esc((c.phones || [])[0] || '') + (c.address ? ' · ' + esc(c.address) : '') + '</small></button>';
                }).join('');
            }).catch(function () { /* no list */ });
    }, 300);

    // ── a customer was just saved in the pop-up: bills and quotes pick them up ──────────────────
    document.body.addEventListener('customer-saved', function (e) {
        var d = e.detail || {};
        var idf = document.querySelector('input[name="customerId"]');
        var namef = document.querySelector('input[name="customerName"]');
        var mobf = document.querySelector('input[name="customerMobile"]');
        if (idf && namef) {
            idf.value = d.id || '';
            namef.value = d.name || '';
            if (mobf) { mobf.value = d.mobile || ''; }
            namef.dispatchEvent(new Event('change', { bubbles: true }));
            var bf = namef.closest('form');
            if (bf) { bf.dispatchEvent(new CustomEvent('customer-changed')); }
        }
    });
})();
