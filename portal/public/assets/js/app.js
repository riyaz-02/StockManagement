/* Portal behaviour. No build step. Alpine runs in its CSP build, so components are defined here (no inline code in the pages). */
(function () {
    'use strict';

    // every htmx request that changes data carries the session's secret token
    document.addEventListener('htmx:configRequest', function (e) {
        var m = document.querySelector('meta[name="csrf"]');
        if (m) e.detail.headers['X-CSRF-Token'] = m.content;
    });

    // ---- toasts (also fired by the server through the HX-Trigger header) ----
    function toast(type, text) {
        var box = document.getElementById('toasts');
        if (!box || !text) return;
        var el = document.createElement('div');
        el.className = 'toast toast-' + (type || 'info');
        el.textContent = text;
        box.appendChild(el);
        setTimeout(function () { el.classList.add('is-out'); setTimeout(function () { el.remove(); }, 300); }, 3500);
    }
    document.body.addEventListener('toast', function (e) { toast(e.detail.type, e.detail.text); });
    window.portalToast = toast;

    // ---- the pop-up window (rate form and later forms) ----
    var modal = function () { return document.getElementById('modal'); };
    document.body.addEventListener('htmx:afterSwap', function (e) {
        if (e.detail.target && e.detail.target.id === 'modal-body' && modal() && !modal().open) modal().showModal();
    });
    document.body.addEventListener('rate-saved', function () { if (modal() && modal().open) modal().close(); });
    document.body.addEventListener('modal-close', function () { if (modal() && modal().open) modal().close(); });
    document.addEventListener('click', function (e) {
        if (e.target.closest('[data-print]')) { window.print(); return; }
        if (e.target.closest('[data-close-modal]') && modal()) modal().close();
        if (e.target === modal()) modal().close();   // click on the dark area
    });

    // ---- audit log: "Details" opens the full before/after list without a server round-trip (it is already on the page) ----
    function escHtml(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; }
    document.addEventListener('click', function (e) {
        var b = e.target.closest('[data-audit-view]');
        if (!b || !modal()) return;
        var d;
        try { d = JSON.parse(b.getAttribute('data-audit-view')); } catch (err) { return; }
        var rows = (d.changes || []).map(function (c) {
            var arrow = c.from ? '<span class="muted">' + escHtml(c.from) + '</span> → ' : '';
            return '<div class="kv-row"><span>' + escHtml(c.field) + '</span><strong>' + arrow + escHtml(c.to) + '</strong></div>';
        }).join('') || '<div class="kv-row"><span class="muted">No field-level changes recorded</span></div>';
        document.getElementById('modal-body').innerHTML =
            '<div class="modal-form">' +
            '<h2>' + escHtml(d.action) + '</h2>' +
            '<p class="muted">' + escHtml(d.where) + ' &middot; ' + escHtml(d.who) + ' &middot; ' + escHtml(d.when) + '</p>' +
            '<div class="kv">' + rows + '</div>' +
            '<div class="modal-actions"><button type="button" class="btn" data-close-modal>Close</button></div>' +
            '</div>';
        modal().showModal();
    });

    // ---- a whole table row opens its page (the number is still a normal link) ----
    document.addEventListener('click', function (e) {
        var tr = e.target.closest && e.target.closest('tr[data-href]');
        if (tr && !e.target.closest('a, button, input, select')) window.location.href = tr.getAttribute('data-href');
    });

    // ---- stock form: net weight = gross - less, until someone types the net themselves ----
    document.addEventListener('input', function (e) {
        var box = e.target.closest && e.target.closest('[data-net-calc]');
        if (!box || !e.target.name) return;
        var f = function (n) { return box.querySelector('[name=' + n + ']'); };
        var net = f('netWeight');
        if (e.target === net) { net.dataset.typed = net.value === '' ? '' : '1'; return; }
        if (e.target.name !== 'grossWeight' && e.target.name !== 'lessWeight') return;
        if (net.dataset.typed === '1') return;
        var g = parseFloat(f('grossWeight').value) || 0, l = parseFloat(f('lessWeight').value) || 0;
        net.value = g > 0 ? Math.max(0, Math.round((g - l) * 1000) / 1000) : '';
    });

    // ---- a filter that applies as soon as it is changed (no button) ----
    document.addEventListener('change', function (e) {
        var t = e.target;
        if (t && t.matches && t.matches('[data-autosubmit]') && t.form) t.form.submit();
    });

    // ---- a button that asks "are you sure?" first (plain forms; htmx buttons use hx-confirm) ----
    document.addEventListener('click', function (e) {
        var b = e.target.closest && e.target.closest('[data-confirm]');
        if (b && !window.confirm(b.getAttribute('data-confirm'))) e.preventDefault();
    });

    // ---- the bill form: remove an item, and Enter must not save the whole bill by accident ----
    function billChanged(form) { if (form) form.dispatchEvent(new Event('change', { bubbles: true })); }
    document.addEventListener('click', function (e) {
        var b = e.target.closest('[data-remove-row]');
        if (!b) return;
        var row = b.closest('[data-row]');
        var form = b.closest('form');
        var box = row && row.parentNode;
        if (!row) return;
        if (box && box.querySelectorAll('[data-row]').length <= 1) {   // keep one empty row rather than none
            row.querySelectorAll('input:not([type=hidden])').forEach(function (i) { i.value = ''; });
        } else if (box) { box.removeChild(row); }
        billChanged(form);
    });
    document.addEventListener('keydown', function (e) {
        if (e.key !== 'Enter' || !e.target.matches || !e.target.matches('input')) return;
        if (e.target.matches('[data-stock-code]')) {
            e.preventDefault();
            var hit = document.querySelector('#stock-hits [data-hit]');
            var btn = e.target.parentNode.querySelector('[data-stock-add]');
            if (hit) hit.click(); else if (btn) btn.click();
        } else if (e.target.closest('form[data-no-enter]')) {
            e.preventDefault();
        }
    });
    document.body.addEventListener('htmx:afterSettle', function (e) {   // a new item row was added: work the total out again
        var t = e.detail && e.detail.target;
        if (t && t.id === 'items') billChanged(t.closest('form'));
    });
    document.body.addEventListener('htmx:afterRequest', function (e) {   // a scan box: clear it and stay ready for the next piece
        var f = e.target;
        if (f && f.matches && f.matches('form[data-reset-after]')) {
            var i = f.querySelector('input[type=text]');
            if (i) { i.value = ''; i.focus(); }
        }
        if (e.target && e.target.matches && e.target.matches('[data-hit]')) {
            var ci = document.querySelector('[data-stock-code]'), hits = document.getElementById('stock-hits');
            if (ci) { ci.value = ''; ci.focus(); }
            if (hits) hits.innerHTML = '';
        }
        if (e.target && e.target.matches && e.target.matches('[data-stock-add]')) {
            var i = e.target.parentNode.querySelector('[data-stock-code]');
            if (i) { i.value = ''; i.focus(); }
        }
    });

    // ---- a failed partial must never leave a blank card: say so ----
    document.body.addEventListener('htmx:responseError', function (e) {
        toast('error', 'Could not load this. Please try again.');
    });
    document.body.addEventListener('htmx:sendError', function () {
        toast('error', 'No connection to the server.');
    });

    // ---- live updates: the API tells this page when something changed (no polling, so an open tab never keeps the server awake) ----
    var live = { es: null, seq: 0, retry: 0, timer: null, hiddenTimer: null };
    function dot(state) {
        var d = document.getElementById('live-dot');
        if (!d) return;
        d.className = 'live-dot' + (state === 'on' ? ' is-on' : (state === 'wait' ? ' is-wait' : ''));
        d.title = state === 'on' ? 'Live: changes appear by themselves' : (state === 'wait' ? 'Reconnecting...' : 'Not live');
    }
    function csrf() { var m = document.querySelector('meta[name="csrf"]'); return m ? m.content : ''; }
    function handle(type, msg) {
        if (msg && msg.seq) { live.seq = Math.max(live.seq, msg.seq); try { sessionStorage.setItem('liveSeq', String(live.seq)); } catch (e) {} }
        if (!window.htmx) return;
        if (type === 'rate.changed') { htmx.trigger(document.body, 'rate-saved'); if (msg.by) toast('info', 'Rate changed by ' + msg.by); }
        else if (type === 'data.changed') { htmx.trigger(document.body, 'data-changed'); }
        else if (type === 'notification.new') { toast('info', (msg.data && msg.data.title) ? msg.data.title : 'New notification'); htmx.trigger(document.body, 'notification-new'); }
        else if (type === 'app.update') { toast('info', 'A new app version is available'); htmx.trigger(document.body, 'notification-new'); }
        else if (type === 'permissions.changed') {
            // access changed: re-read it and rebuild the page so the menu and buttons match
            fetch('/session/refresh', { method: 'POST', headers: { 'X-CSRF-Token': csrf() }, credentials: 'same-origin' })
                .then(function () { toast('info', 'Your access was updated'); setTimeout(function () { location.reload(); }, 900); });
        }
    }
    function connect() {
        if (live.es || !document.body.dataset.live) return;
        dot('wait');
        fetch('/live/ticket', { method: 'POST', headers: { 'X-CSRF-Token': csrf(), 'Accept': 'application/json' }, credentials: 'same-origin' })
            .then(function (r) { if (r.status === 401) { location.href = '/login'; throw new Error('signed out'); } return r.ok ? r.json() : Promise.reject(new Error('no ticket')); })
            .then(function (j) {
                var since = live.seq || parseInt(sessionStorage.getItem('liveSeq') || '0', 10) || 0;
                var es = new EventSource(j.url + '?ticket=' + encodeURIComponent(j.ticket) + (since ? '&since=' + since : ''));
                live.es = es;
                es.addEventListener('hello', function (e) {
                    var m = JSON.parse(e.data);
                    live.retry = 0; dot('on');
                    if (m.reset) { htmx.trigger(document.body, 'data-changed'); htmx.trigger(document.body, 'rate-saved'); }
                    if (!since && m.latest) live.seq = m.latest;
                });
                ['rate.changed', 'data.changed', 'notification.new', 'app.update', 'permissions.changed', 'settings.changed'].forEach(function (t) {
                    es.addEventListener(t, function (e) { try { handle(t, JSON.parse(e.data)); } catch (x) {} });
                });
                // a ticket works once, so the browser's own automatic reconnect cannot work: close and ask for a new one
                es.onerror = function () { es.close(); live.es = null; dot('wait'); schedule(); };
            })
            .catch(function () { live.es = null; dot('wait'); schedule(); });
    }
    function schedule() {
        clearTimeout(live.timer);
        live.retry = Math.min(live.retry + 1, 6);
        live.timer = setTimeout(connect, Math.min(60000, 2000 * Math.pow(2, live.retry - 1)));
    }
    function stop() { clearTimeout(live.timer); if (live.es) { live.es.close(); live.es = null; } dot('off'); }
    if (document.body.dataset.live) {
        connect();
        // a hidden tab lets go after a minute and catches up when it comes back
        document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'hidden') { live.hiddenTimer = setTimeout(stop, 60000); }
            else { clearTimeout(live.hiddenTimer); if (!live.es) { live.retry = 0; connect(); } }
        });
    }

    // ---- presence: "I'm here, on this screen" for Staff & Roles > Live now. Only while the tab is actually visible. ----
    if (document.body.dataset.live) {
        var ping = function () {
            if (document.visibilityState !== 'visible') return;
            fetch('/presence/ping', { method: 'POST', headers: { 'X-CSRF-Token': csrf(), 'Content-Type': 'application/json' }, credentials: 'same-origin', body: JSON.stringify({ screen: document.body.dataset.screen || '' }) }).catch(function () {});
        };
        ping();
        setInterval(ping, 20000);
        document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') ping(); });
    }

    document.addEventListener('alpine:init', function () {
        // side menu on phones
        Alpine.data('shell', function () {
            var saved = null;
            try { saved = localStorage.getItem('menuCollapsed'); } catch (e) {}
            return {
                open: false,
                // wide screens remember the choice; a tablet starts collapsed to leave room for the page
                collapsed: saved === null ? (window.innerWidth < 1200 || !!document.querySelector('.pos')) : saved === '1',
                menu: function () {
                    if (window.innerWidth <= 900) { this.open = !this.open; return; }
                    this.collapsed = !this.collapsed;
                    try { localStorage.setItem('menuCollapsed', this.collapsed ? '1' : '0'); } catch (e) {}
                },
                toggle: function () { this.open = !this.open; },
                close: function () { this.open = false; },
                get sidebarClass() { return this.open ? 'sidebar is-open' : 'sidebar'; },
                get shellClass() { return this.collapsed ? 'shell is-collapsed' : 'shell'; }
            };
        });

        // the bell in the top bar: opening it loads the list (the page uses the CSP-safe Alpine, so no inline code in the markup)
        Alpine.data('bell', function () {
            return {
                open: false,
                toggle: function () {
                    this.open = !this.open;
                    if (this.open && window.htmx) htmx.trigger(document.getElementById('bell-list'), 'bell-open');
                },
                close: function () { this.open = false; }
            };
        });

        // customer search box: pick a saved customer (fills id, name and mobile) or keep the typed name
        Alpine.data('picker', function () {
            return {
                open: false,
                typed: function (e) {
                    var f = this.$root.closest('form');
                    var id = f && f.querySelector('[name=customerId]');
                    if (id) id.value = '';                       // typing again means "not a saved customer" until one is picked
                    this.open = (e.target.value || '').trim().length >= 2;
                },
                hide: function () { this.open = false; },
                pick: function (e) {
                    var it = e.target.closest('.picker-item');
                    if (!it) return;
                    var f = this.$root.closest('form');
                    if (it.dataset.new) { this.open = false; return; }   // "use the typed name"
                    f.querySelector('[name=customerId]').value = it.dataset.id || '';
                    f.querySelector('[name=customerName]').value = it.dataset.name || '';
                    var m = f.querySelector('[name=customerMobile]');
                    if (m && it.dataset.mobile) m.value = it.dataset.mobile;
                    this.open = false;
                    f.dispatchEvent(new CustomEvent('customer-changed'));
                }
            };
        });

        // show / hide the password
        Alpine.data('passwordField', function () {
            return {
                shown: false,
                toggle: function () { this.shown = !this.shown; },
                get type() { return this.shown ? 'text' : 'password'; },
                get label() { return this.shown ? 'Hide' : 'Show'; }
            };
        });

        // the "Starting the server" screen
        Alpine.data('wake', function () {
            return {
                state: 'checking', seconds: 0, ready: false, slow: false, step: 0, timer: null, asked: false,
                init: function () {
                    var self = this;
                    this.begin();
                    this.timer = setInterval(function () { self.tick(); }, 3000);
                    document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') self.tick(); });
                },
                cfg: function (k) { return this.$root.dataset[k]; },
                begin: function () {
                    this.seconds = 0; this.slow = false; this.ready = false; this.step = 0; this.asked = false;
                    this.tick();
                },
                get message() {
                    if (this.ready) return this.cfg('lReady');
                    if (this.slow) return this.cfg('lSlow');
                    if (this.seconds === 0) return this.cfg('lChecking');
                    return this.cfg('lStarting').replace('{s}', this.seconds);
                },
                get pulseClass() { return this.ready ? 'pulse is-ready' : (this.slow ? 'pulse is-slow' : 'pulse'); },
                get s1() { return this.step >= 1 ? 'done' : 'now'; },
                get s2() { return this.step >= 2 ? 'done' : (this.step === 1 ? 'now' : ''); },
                get s3() { return this.step >= 3 ? 'done' : (this.step === 2 ? 'now' : ''); },
                get barStyle() {
                    var p = this.ready ? 100 : Math.min(92, 8 + this.seconds * 0.9);
                    return 'width:' + p + '%';
                },
                post: function (url) {
                    return fetch(url, { method: 'POST', headers: { 'X-CSRF-Token': this.cfg('csrf'), 'Accept': 'application/json' }, credentials: 'same-origin' })
                        .then(function (r) { return r.json(); });
                },
                tick: function () {
                    var self = this;
                    fetch('/wake/status', { headers: { 'Accept': 'application/json' }, credentials: 'same-origin', cache: 'no-store' })
                        .then(function (r) { return r.json(); })
                        .then(function (j) {
                            if (j.state === 'online') {
                                self.ready = true; self.step = 3;
                                clearInterval(self.timer);
                                setTimeout(function () { window.location.href = self.cfg('next') || '/'; }, 700);
                                return;
                            }
                            self.seconds += 3;
                            if (j.state === 'starting') { self.step = 2; }
                            else {
                                self.step = self.asked ? 1 : 0;
                                if (!self.asked) { self.asked = true; self.post('/wake/start').then(function () { self.step = 1; }).catch(function () {}); }
                            }
                            if (self.seconds > 240) { self.slow = true; clearInterval(self.timer); }
                        })
                        .catch(function () { self.seconds += 3; });
                },
                retry: function () {
                    var self = this;
                    clearInterval(this.timer);
                    this.begin();
                    this.timer = setInterval(function () { self.tick(); }, 3000);
                }
            };
        });
    });
})();
