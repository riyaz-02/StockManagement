<?php
declare(strict_types=1);

/**
 * End-to-end test of the portal against a RUNNING portal and a RUNNING dev API:
 *   php -S localhost:8080 -t public router.php     (portal)
 *   node server.js                                 (backend, dev database)
 *   php tests/smoke.php [http://localhost:8080]
 * Uses the local dev logins from CLAUDE.md. Never run against production.
 */
$base = rtrim($argv[1] ?? 'http://localhost:8080', '/');
$pass = 0;
$fail = 0;
function check(string $name, bool $ok, string $detail = ''): void
{
    global $pass, $fail;
    if ($ok) { $pass++; echo "  ok    $name\n"; } else { $fail++; echo "  FAIL  $name $detail\n"; }
}

require __DIR__ . '/Browser.php';

echo "Signed out\n";
$b = new Browser($base);
$r = $b->req('GET', '/');
check('the home page sends a signed-out person to the login', $r['code'] === 302 && str_ends_with($r['headers']['location'] ?? '', '/login'));
$r = $b->req('GET', '/partials/dashboard');
check('a partial is not readable without signing in', $r['code'] === 302);
$r = $b->req('GET', '/login');
check('the login page opens', $r['code'] === 200 && str_contains($r['body'], 'name="mobile"'));
check('security headers are sent', str_contains($r['headers']['content-security-policy'] ?? '', "script-src 'self'") && ($r['headers']['x-frame-options'] ?? '') === 'DENY' && ($r['headers']['x-content-type-options'] ?? '') === 'nosniff');
check('pages are never cached', str_contains($r['headers']['cache-control'] ?? '', 'no-store'));
$r = $b->req('POST', '/login', ['mobile' => '7029621489', 'password' => 'Admin@123']);
check('a login form without its secret token is refused (419)', $r['code'] === 419);
$r = $b->login('7029621489', 'wrong-password');
check('a wrong password shows a message and does not sign in', $r['code'] === 200 && str_contains($r['body'], 'is wrong') && $b->req('GET', '/')['code'] === 302);
$r = $b->req('GET', '/nothing-here');
check('an unknown page is a clean 404', $r['code'] === 302 || $r['code'] === 404);

echo "\nAdmin\n";
$a = new Browser($base);
$r = $a->login('7029621489', 'Admin@123');
check('the admin signs in and lands on Home', $r['code'] === 302 && ($r['headers']['location'] ?? '') === '/');
$home = $a->req('GET', '/');
check('Home shows the name, the menu and the admin section', $home['code'] === 200 && str_contains($home['body'], 'Hello, Admin') && str_contains($home['body'], 'Admin Control') && str_contains($home['body'], 'GST Billing'));
$d = $a->req('GET', '/partials/dashboard', [], ['HX-Request: true']);
check('the dashboard numbers come from the API (sales, dues, orders)', $d['code'] === 200 && str_contains($d['body'], 'Sales today') && str_contains($d['body'], 'Pending dues') && str_contains($d['body'], 'Customer orders'), substr($d['body'], 0, 120));
$s = $a->req('GET', '/partials/rate');
check('the rate strip loads', $s['code'] === 200 && str_contains($s['body'], 'rate-cell'));
$f = $a->req('GET', '/partials/rate-form');
check('the admin may open the rate form', $f['code'] === 200 && str_contains($f['body'], 'name="gold"'));
$tok = $a->csrf('/');
$r = $a->req('POST', '/rates', ['gold' => '14100', 'silver' => '171']);
check('changing the rate without the token is refused (419)', $r['code'] === 419);
$r = $a->req('POST', '/rates', ['gold' => '14100', 'silver' => '171'], ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);
check('changing the rate with the token works and tells the page to refresh', $r['code'] === 204 && str_contains($r['headers']['hx-trigger'] ?? '', 'rate-saved'), (string) $r['code']);
$s = $a->req('GET', '/partials/rate');
check('the new rate is shown', str_contains($s['body'], '14,100') && str_contains($s['body'], '171'));
$r = $a->req('POST', '/rates', ['gold' => '92', 'silver' => ''], ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);
check('a typing slip is refused by the API and shown in the form (422)', $r['code'] === 422 && str_contains($r['body'], 'looks wrong'), (string) $r['code']);
$r = $a->req('GET', '/nowhere-at-all');
check('an address that does not exist shows the friendly not-found page', $r['code'] === 404 && str_contains($r['body'], 'was not found'));
$r = $a->req('GET', '/admin/staff');
check('an admin page opens for the admin', $r['code'] === 200);
$r = $a->req('POST', '/live/ticket', [], ['X-CSRF-Token: ' . $tok]);
$tj = json_decode($r['body'], true);
check('the page gets a one-time live ticket (the browser never sees the login token)', $r['code'] === 200 && preg_match('/^[a-f0-9]{48}$/', (string) ($tj['ticket'] ?? '')) === 1 && str_ends_with((string) ($tj['url'] ?? ''), '/api/live') && !str_contains($r['body'], 'eyJ'));
check('the live ticket needs the secret token too (419)', $a->req('POST', '/live/ticket')['code'] === 419);
$r = $a->req('POST', '/session/refresh', [], ['X-CSRF-Token: ' . $tok]);
check('the page can re-read a persons permissions after an admin changed them', $r['code'] === 200 && (json_decode($r['body'], true)['ok'] ?? false) === true);
check('the live endpoints are closed to signed-out people', (new Browser($base))->req('POST', '/live/ticket')['code'] === 419);
$r = $a->req('GET', '/does-not-exist');
check('an unknown page is a 404 page, not an error', $r['code'] === 404 && str_contains($r['body'], '404'));

echo "\nStaff (limited role)\n";
$st = new Browser($base);
$r = $st->login('9000000011', 'Staff@123');
check('a branch staff member signs in', $r['code'] === 302, (string) $r['code']);
$home = $st->req('GET', '/');
check('their menu has no Admin Control section', $home['code'] === 200 && !str_contains($home['body'], 'Admin Control') && !str_contains($home['body'], 'Staff &amp; roles'));
$r = $st->req('GET', '/admin/staff');
check('an admin page is refused for them (403 page, nothing leaks)', $r['code'] === 403);
$d = $st->req('GET', '/partials/dashboard', [], ['HX-Request: true']);
check('they see only the cards they may see (no Day Book money)', $d['code'] === 200 && !str_contains($d['body'], 'Money in today'));
$st->req('POST', '/logout', ['_csrf' => $st->csrf('/')]);
check('signing out ends the session', $st->req('GET', '/')['code'] === 302);

echo "\nSession safety\n";
$c = new Browser($base);
$c->login('7029621489', 'Admin@123');
$before = $c->req('GET', '/');
$r = $c->req('POST', '/logout');
check('sign-out without the token is refused (419): no forced logout from another site', $r['code'] === 419 && $c->req('GET', '/')['code'] === 200);
$c->req('POST', '/logout', ['_csrf' => $c->csrf('/')]);
check('sign-out with the token works', $c->req('GET', '/')['code'] === 302);

echo "\n$pass passed, $fail failed\n";
exit($fail ? 1 : 0);
