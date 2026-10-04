<?php
declare(strict_types=1);

/**
 * Admin Control > Branches & counters, the "Working at" drop-downs and the Counter drop-down on the staff forms, against a
 * RUNNING portal and dev API:  php tests/branches.php [http://localhost:8080] [http://localhost:5000/api]
 * Makes a branch called "PT Branch <tag>" (with counters and a person) in the DEV database and removes it again at the end.
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
function apiCall(string $method, string $url, ?array $body = null, string $token = '', array $headers = []): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 20,
        CURLOPT_HTTPHEADER => array_merge(array_filter(['Content-Type: application/json', $token ? 'Authorization: Bearer ' . $token : '']), $headers)]);
    if ($body !== null) { curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body)); }
    $out = (string) curl_exec($ch);
    curl_close($ch);
    return (array) json_decode($out, true);
}

$tag = strtoupper(substr(md5((string) microtime(true)), 0, 5));
$name = "PT Branch $tag";
$HX = ['HX-Request: true'];
$a = new Browser($base);
$a->login('7029621489', 'Admin@123');
$tok = $a->csrf('/');
$s = new Browser($base);
$s->login('9000000011', 'Staff@123');
$stok = $s->csrf('/');
$at = apiCall('POST', $api . '/auth/login', ['mobile' => '7029621489', 'password' => 'Admin@123'])['data']['token'] ?? '';

echo "Branches & counters\n";
$r = $a->req('GET', '/admin/branches');
check('the page opens for an admin: the branches and the form to open one', $r['code'] === 200 && str_contains($r['body'], 'Open a new branch') && str_contains($r['body'], 'Main branch'), (string) $r['code']);
check('it is in the Admin Control menu', str_contains($a->req('GET', '/')['body'], '/admin/branches'));
check('a staff login cannot open it or change anything (403)', $s->req('GET', '/admin/branches')['code'] === 403 && $s->req('POST', '/admin/branches', ['_csrf' => $stok, 'name' => 'x'])['code'] === 403);

$r = $a->req('POST', '/admin/branches', ['_csrf' => $tok, 'name' => '']);
check('no name is explained (422)', $r['code'] === 422 && str_contains($r['body'], 'Branch name is required'), (string) $r['code']);
$r = $a->req('POST', '/admin/branches', ['_csrf' => $tok, 'name' => $name, 'invoicePrefix' => 'P' . substr($tag, 0, 3), 'gstin' => 'bad']);
check('a bad GSTIN is explained (422)', $r['code'] === 422 && str_contains($r['body'], 'GSTIN must be 15'), (string) $r['code']);
$r = $a->req('POST', '/admin/branches', ['_csrf' => $tok, 'name' => $name, 'invoicePrefix' => 'P' . substr($tag, 0, 3), 'city' => 'Howrah', 'state' => 'West Bengal']);
$loc = $r['headers']['location'] ?? '';
check('opening a branch goes to its page', $r['code'] === 302 && preg_match('#^/admin/branches/([a-f0-9]{24})$#', $loc, $m) === 1, (string) $r['code'] . ' ' . $loc);
$bid = $m[1] ?? '';
$r = $a->req('GET', "/admin/branches/$bid");
check('its page shows the name, the bill letters and the counters panel', $r['code'] === 200 && str_contains($r['body'], $name) && str_contains($r['body'], 'Billing counters') && str_contains($r['body'], 'P' . substr($tag, 0, 3)), (string) $r['code']);
$r = $a->req('POST', '/admin/branches', ['_csrf' => $tok, 'name' => strtolower($name)]);
check('the same name again is refused (422)', $r['code'] === 422 && str_contains($r['body'], 'already exists'));

$r = $a->req('POST', "/admin/branches/$bid", ['_csrf' => $tok, 'name' => $name, 'city' => 'Kolkata', 'invoicePrefix' => 'P' . substr($tag, 0, 3), 'isActive' => '1']);
$b = apiCall('GET', "$api/branches/$bid", null, $at)['data'] ?? [];
check('the details can be changed', $r['code'] === 302 && ($b['city'] ?? '') === 'Kolkata', json_encode($b));

$r = $a->req('POST', "/admin/branches/$bid/counters", ['_csrf' => $tok, 'name' => 'Counter 1', 'code' => 'c1']);
$r2 = $a->req('POST', "/admin/branches/$bid/counters", ['_csrf' => $tok, 'name' => 'Gold desk']);
$r3 = $a->req('POST', "/admin/branches/$bid/counters", ['_csrf' => $tok, 'name' => 'counter 1']);
check('two counters are added, a repeated name is refused (422)', $r['code'] === 302 && $r2['code'] === 302 && $r3['code'] === 422 && str_contains($r3['body'], 'already has a counter'), "{$r['code']} {$r2['code']} {$r3['code']}");
$counters = apiCall('GET', "$api/branches/$bid/counters", null, $at)['data']['counters'] ?? [];
$c1 = '';
$c2 = '';
foreach ($counters as $c) { if ($c['name'] === 'Counter 1') { $c1 = $c['id']; } if ($c['name'] === 'Gold desk') { $c2 = $c['id']; } }
check('the API holds both (code in capitals)', $c1 !== '' && $c2 !== '' && ($counters[0]['code'] ?? '') !== '');
$r = $a->req('POST', "/admin/branches/$bid/counters/$c2", ['_csrf' => $tok, 'name' => 'Gold counter', 'code' => 'G', 'note' => 'near the door', 'isActive' => '1']);
$c = array_values(array_filter(apiCall('GET', "$api/branches/$bid/counters", null, $at)['data']['counters'] ?? [], fn ($x) => $x['id'] === $c2))[0] ?? [];
check('a counter can be renamed and given a note', $r['code'] === 302 && ($c['name'] ?? '') === 'Gold counter' && ($c['note'] ?? '') === 'near the door');

echo "\nWho works where\n";
$r = $a->req('GET', '/admin/staff/new', [], $HX);
check('the new-staff form has a Counter drop-down with the counters of every branch', $r['code'] === 200 && str_contains($r['body'], 'data-counter-select') && str_contains($r['body'], 'Gold counter'));
$mob = '93' . str_pad((string) random_int(0, 99999999), 8, '7', STR_PAD_LEFT);
$r = $a->req('POST', '/admin/staff', ['_csrf' => $tok, 'name' => "PT Person $tag", 'mobile' => $mob, 'password' => 'Pt@123456', 'role' => 'staff', 'branchId' => $bid, 'counterId' => $c1], $HX);
$people = apiCall('GET', "$api/branches/$bid", null, $at)['data']['staff'] ?? [];
$me = array_values(array_filter($people, fn ($p) => $p['mobile'] === $mob))[0] ?? [];
check('a person is added at the branch with a counter', ($me['counterName'] ?? '') === 'Counter 1', json_encode($people));
$uid = $me['id'] ?? '';
$r = $a->req('GET', "/admin/staff/$uid");
check('their page shows the Counter drop-down with their counter chosen', $r['code'] === 200 && str_contains($r['body'], 'data-counter-select') && (bool) preg_match('/value="' . $c1 . '"[^>]*selected/', $r['body']));
$r = $a->req('GET', "/admin/branches/$bid");
check("the branch page lists them with their counter", str_contains($r["body"], "PT Person $tag") && (bool) preg_match('/value="' . $c1 . '" selected/', $r["body"]));
$r = $a->req('POST', "/admin/branches/$bid/staff/$uid", ['_csrf' => $tok, 'counterId' => $c2]);
$people = apiCall('GET', "$api/branches/$bid", null, $at)['data']['staff'] ?? [];
$me = array_values(array_filter($people, fn ($p) => $p['id'] === $uid))[0] ?? [];
check('their counter can be changed from the branch page', $r['code'] === 302 && ($me['counterName'] ?? '') === 'Gold counter');
$r = $a->req('POST', "/admin/staff/$uid", ['_csrf' => $tok, 'name' => "PT Person $tag", 'mobile' => $mob, 'role' => 'staff', 'branchId' => 'main', 'isActive' => '1']);
$u = apiCall('GET', "$api/users/$uid", null, $at)['data']['user'] ?? [];
check('moving them to the main branch drops the old counter', ($u['branchId'] ?? '') === 'main' && ($u['counterId'] ?? '') === '', json_encode($u));
$r = $a->req('POST', "/admin/branches/$bid/staff", ['_csrf' => $tok, 'uid' => $uid, 'counterId' => $c1]);
$u = apiCall('GET', "$api/users/$uid", null, $at)['data']['user'] ?? [];
check('"Move a person here" brings them back with a counter', $r['code'] === 302 && ($u['branchId'] ?? '') === $bid && ($u['counterId'] ?? '') === $c1);

echo "\nWorking at\n";
$r = $a->req('GET', '/partials/workplace', [], $HX);
check('the top bar drop-down for an admin lists the branches', $r['code'] === 200 && str_contains($r['body'], 'Whole firm') && str_contains($r['body'], $name), substr($r['body'], 0, 120));
$r = $a->req('POST', '/workplace', ['branch' => $bid], ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);
check('choosing a branch reloads the page (HX-Refresh)', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true');
$r = $a->req('GET', '/partials/workplace', [], $HX);
check('the counters of that branch are offered, the branch is selected', str_contains($r['body'], 'Counter 1') && (bool) preg_match('/value="' . $bid . '" selected/', $r['body']), substr($r['body'], 0, 200));
$a->req('POST', '/workplace', ['counter' => $c1], ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);
$r = $a->req('GET', '/partials/workplace', [], $HX);
check('the chosen counter is remembered', (bool) preg_match('/value="' . $c1 . '" selected/', $r['body']));
$a->req('POST', '/workplace', ['branch' => ''], ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);
$rs = $s->req('GET', '/partials/workplace', [], $HX);
check('a staff login sees no branch switch (only their counters, if any)', !str_contains($rs['body'], 'Whole firm'));

// tidy up: the person, the counters and the branch made here (removed straight from the DEV database)
$js = sys_get_temp_dir() . '/lgp-branches-cleanup.js';
file_put_contents($js, 'const {MongoClient,ObjectId}=require(process.argv[2]+"/mongodb");(async()=>{const c=await MongoClient.connect("mongodb://127.0.0.1:27018");const d=c.db("lgp_dev");'
    . 'await d.collection("users").deleteMany({_id:new ObjectId(process.argv[4])});await d.collection("app_branch_counters").deleteMany({branchId:process.argv[3]});'
    . 'await d.collection("app_branches").deleteMany({_id:new ObjectId(process.argv[3])});await c.close();})();');
if ($bid !== '' && $uid !== '') {
    shell_exec('node ' . escapeshellarg($js) . ' ' . escapeshellarg(str_replace(chr(92), '/', (string) realpath(__DIR__ . '/../../backend/node_modules'))) . ' ' . escapeshellarg($bid) . ' ' . escapeshellarg($uid));
}
@unlink($js);

echo "\n$pass passed, $fail failed\n";
exit($fail ? 1 : 0);
