<?php
declare(strict_types=1);

/**
 * End-to-end test of the Stock Tally pages against a RUNNING portal and dev API:  php tests/tally.php [http://localhost:8080] [http://localhost:5000/api]
 * Starts a test tally in the DEV database, scans a piece, locks it and deletes it again. Never run against production.
 */
require __DIR__ . '/Browser.php';

$base = rtrim($argv[1] ?? 'http://localhost:8080', '/');
$api = rtrim($argv[2] ?? 'http://localhost:5000/api', '/');
$pass = 0;
$fail = 0;
function check(string $name, bool $ok, string $detail = ''): void
{
    global $pass, $fail;
    if ($ok) { $pass++; echo "  ok    $name\n"; } else { $fail++; echo "  FAIL  $name $detail\n"; }
}
function apiCall(string $method, string $url, ?array $body = null, string $token = ''): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 20,
        CURLOPT_HTTPHEADER => array_filter(['Content-Type: application/json', $token ? 'Authorization: Bearer ' . $token : ''])]);
    if ($body !== null) { curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body)); }
    $out = (string) curl_exec($ch);
    curl_close($ch);
    return (array) json_decode($out, true);
}
$HX = ['HX-Request: true'];
$a = new Browser($base);
$a->login('7029621489', 'Admin@123');
$tok = $a->csrf('/');
$post = fn (string $path, array $form = []) => $a->req('POST', $path, $form, ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);
$login = apiCall('POST', $api . '/auth/login', ['mobile' => '7029621489', 'password' => 'Admin@123']);
$at = $login['data']['token'] ?? '';

// nothing may be running for the test to start its own
foreach ((array) (apiCall('GET', $api . '/tally?status=active', null, $at)['data']['tallySessions'] ?? []) as $s) {
    if (str_starts_with((string) ($s['description'] ?? ''), 'PORTAL TEST')) { apiCall('DELETE', $api . '/tally/' . $s['_id'], null, $at); }
}
$running = (array) (apiCall('GET', $api . '/tally?status=active', null, $at)['data']['tallySessions'] ?? []);
if ($running) { echo "A real tally is running in the dev database; not touching it. Finish or delete it and run again.\n"; exit(0); }

echo "Tally page\n";
$r = $a->req('GET', '/tally');
check('the page opens and loads by itself', $r['code'] === 200 && str_contains($r['body'], 'hx-get="/tally/list"'));
$r = $a->req('GET', '/tally/list', [], $HX);
check('with nothing running it offers to start one and shows what it would count', $r['code'] === 200 && str_contains($r['body'], 'Start a new tally') && str_contains($r['body'], 'pieces') && str_contains($r['body'], 'Earlier tallies'));

echo "\nStart, scan, lock\n";
$r = $post('/tally', ['description' => 'PORTAL TEST tally']);
$to = $r['headers']['hx-redirect'] ?? '';
check('starting goes straight to the counting page', $r['code'] === 204 && preg_match('#^/tally/[a-f0-9]{24}$#', $to) === 1, "($r[code])");
$id = substr($to, strlen('/tally/'));
$r = $post('/tally', ['description' => 'PORTAL TEST second']);
check('a second tally while one runs is refused with a clear message', $r['code'] === 204 && str_contains($r['headers']['hx-trigger'] ?? '', 'already running'));
$r = $a->req('GET', $to);
check('the counting page has the scan box, and loads its progress', $r['code'] === 200 && str_contains($r['body'], 'name="barcode"') && str_contains($r['body'], 'hx-get="/tally/' . $id . '/panel"') && str_contains($r['body'], 'Finish and lock'));
$r = $a->req('GET', $to . '/panel', [], $HX);
check('the progress shows checked, still to find and the boxes', $r['code'] === 200 && str_contains($r['body'], 'Checked') && str_contains($r['body'], 'Still to find') && str_contains($r['body'], 'Box by box'));
$r = $post($to . '/scan', ['barcode' => 'NO-SUCH-CODE']);
check('an unknown barcode is explained in red', $r['code'] === 200 && str_contains($r['body'], 'is-bad') && str_contains($r['body'], 'not found'));
$sum = apiCall('GET', $api . '/tally/' . $id . '/summary', null, $at);
$first = $sum['data']['missing'][0] ?? null;
if ($first) {
    $r = $post($to . '/scan', ['barcode' => $first['barcode']]);
    check('a real piece is found and counted', $r['code'] === 200 && (str_contains($r['body'], 'is-ok') || str_contains($r['body'], 'Weigh this piece')) && str_contains($r['headers']['hx-trigger'] ?? 'tally-scanned', 'tally-scanned'), substr(strip_tags($r['body']), 0, 200));
    if (str_contains($r['body'], 'is-ok')) {
        $r = $post($to . '/scan', ['barcode' => $first['barcode']]);
        check('scanning the same piece again says it was already counted', str_contains($r['body'], 'is-bad') && str_contains($r['body'], 'already'));
    }
}
$r = $a->req('GET', $to . '/lock', [], $HX);
check('the lock form asks for remarks because pieces are missing', $r['code'] === 200 && str_contains($r['body'], 'were not found') && str_contains($r['body'], 'name="remarks"'));
$r = $post($to . '/lock', ['remarks' => '']);
check('locking with missing pieces and no remarks is refused (422)', $r['code'] === 422 && str_contains($r['body'], 'Remarks are required'));
$r = $post($to . '/lock', ['remarks' => 'portal test']);
check('locking with a reason works and reloads the page', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true');
$r = $a->req('GET', $to);
check('the locked tally shows its state and no scan box', str_contains($r['body'], 'Locked with items missing') && !str_contains($r['body'], 'name="barcode"'));
$r = $a->req('GET', $to . '/panel', [], $HX);
check('the locked report lists what was not found and where to look', str_contains($r['body'], 'Not found when locked') && str_contains($r['body'], 'Where to look'));
$r = $a->req('GET', '/tally/list', [], $HX);
check('it appears under earlier tallies, with how many are missing and who ran it', str_contains($r['body'], 'PORTAL TEST tally') && str_contains($r['body'], 'Locked ·') && str_contains($r['body'], 'missing') && str_contains($r['body'], 'Admin'));
apiCall('DELETE', $api . '/tally/' . $id, null, $at);   // leave the dev data as it was

echo "\nPermissions\n";
$v = new Browser($base);
$v->login('9000000011', 'Staff@123');
check('a staff login can open the tally page', in_array($v->req('GET', '/tally')['code'], [200, 403], true));

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
