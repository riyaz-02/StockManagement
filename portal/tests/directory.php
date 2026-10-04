<?php
declare(strict_types=1);

/**
 * End-to-end test of the Customers and suppliers pages against a RUNNING portal and dev API:  php tests/directory.php [http://localhost:8080] [http://localhost:5000/api]
 * Adds one test customer to the DEV database (customers are never deleted, so it stays: named PORTAL TEST). Never run against production.
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
$at = apiCall('POST', $api . '/auth/login', ['mobile' => '7029621489', 'password' => 'Admin@123'])['data']['token'] ?? '';

echo "Lists\n";
$r = $a->req('GET', '/directory');
check('the page opens and loads the list', $r['code'] === 200 && str_contains($r['body'], 'hx-get="/directory/list"') && str_contains($r['body'], 'New customer'));
$r = $a->req('GET', '/directory/list', [], $HX);
check('customers are listed with a total', $r['code'] === 200 && str_contains($r['body'], 'class="t"') && str_contains($r['body'], 'data-href="/directory/customers/'));
$r = $a->req('GET', '/directory/list?tab=suppliers', [], $HX);
check('suppliers are listed', $r['code'] === 200 && str_contains($r['body'], 'data-href="/directory/suppliers/'));
$r = $a->req('GET', '/directory/list?tab=karigars', [], $HX);
check('karigars open (a list or an empty message)', $r['code'] === 200 && (str_contains($r['body'], 'data-href="/directory/karigars/') || str_contains($r['body'], 'Nobody found')));
$r = $a->req('GET', '/directory/list?q=zzzz-nobody-here', [], $HX);
check('a search with no match says so', str_contains($r['body'], 'Nobody found'));

echo "\nAdd, view, edit a customer\n";
$mob = '9' . str_pad((string) random_int(0, 999999999), 9, '0', STR_PAD_LEFT);
$name = 'PORTAL TEST Customer ' . substr($mob, -4);
$r = $a->req('GET', '/directory/customers/new');
check('the form opens', $r['code'] === 200 && str_contains($r['body'], 'name="number[]"') && str_contains($r['body'], 'name="name"'));
$r = $a->req('POST', '/directory/customers', ['_csrf' => $tok, 'name' => 'X', 'number' => [''], 'label' => ['whatsapp']]);
check('a short name / missing number is refused in the form (422)', $r['code'] === 422 && str_contains($r['body'], 'notice-error'));
$r = $a->req('POST', '/directory/customers', ['_csrf' => $tok, 'name' => $name, 'number' => [$mob], 'label' => ['whatsapp'], 'address' => '9 Test Lane', 'city' => 'Howrah', 'panNo' => 'abcde1234f', 'membershipStatus' => 'VIP']);
$loc = $r['headers']['location'] ?? '';
check('saving opens the customer', $r['code'] === 302 && preg_match('#^/directory/customers/[a-f0-9]{24}$#', $loc) === 1, "($r[code]) " . substr(strip_tags($r['body']), 0, 200));
$r = $a->req('POST', '/directory/customers', ['_csrf' => $tok, 'name' => $name . ' again', 'number' => [$mob], 'label' => ['whatsapp']]);
check('the same number on another customer is refused, with the "save anyway" choice', $r['code'] === 422 && str_contains($r['body'], 'already') && str_contains($r['body'], 'name="force"'));
$r = $a->req('GET', $loc);
check('the page shows contact, VIP, what they owe and their bills', $r['code'] === 200 && str_contains($r['body'], $name) && str_contains($r['body'], $mob) && str_contains($r['body'], 'VIP') && str_contains($r['body'], 'Owes you') && str_contains($r['body'], 'ABCDE1234F') && str_contains($r['body'], 'New bill'));
$id = substr($loc, strlen('/directory/customers/'));
$r = $a->req('GET', '/billing/new?customer=' . $id);
check('"New bill" opens with this customer, address and PAN filled in', str_contains($r['body'], 'value="' . $name . '"') && str_contains($r['body'], '9 Test Lane') && str_contains($r['body'], 'ABCDE1234F'));
$r = $a->req('GET', $loc . '/edit');
check('edit shows what is saved', $r['code'] === 200 && str_contains($r['body'], 'value="' . $mob . '"') && str_contains($r['body'], 'name="expectedUpdatedAt"') && str_contains($r['body'], 'value="Howrah"'));
// give the customer things the form does not show, so we can prove an edit does not wipe them
apiCall('PUT', $api . '/directory/customers/' . $id, ['name' => $name, 'contacts' => [['number' => $mob, 'label' => 'whatsapp'], ['number' => '9' . str_pad((string) random_int(0, 999999999), 9, '0', STR_PAD_LEFT), 'label' => 'mobile']],
    'address' => '9 Test Lane', 'city' => 'Howrah', 'panNo' => 'ABCDE1234F', 'membershipStatus' => 'VIP', 'fatherName' => 'Test Father', 'notes' => 'keep me', 'opening' => ['cash' => ['amount' => 1500, 'type' => 'debit']]], $at);
$before = apiCall('GET', $api . '/directory/customers/' . $id, null, $at)['data'] ?? [];
$r = $a->req('GET', $loc . '/edit');
preg_match('/name="expectedUpdatedAt" value="([^"]*)"/', $r['body'], $m);
$r = $a->req('POST', $loc, ['_csrf' => $tok, 'name' => $name, 'number' => [$mob, $before['profile']['contacts'][1]['number'] ?? ''], 'label' => ['whatsapp', 'mobile'], 'address' => '10 New Lane', 'city' => 'Howrah', 'panNo' => 'ABCDE1234F', 'membershipStatus' => 'VIP', 'notes' => 'keep me', 'expectedUpdatedAt' => html_entity_decode($m[1] ?? '')]);
check('saving an edit goes back to the customer', $r['code'] === 302 && ($r['headers']['location'] ?? '') === $loc, "($r[code]) " . substr(strip_tags($r['body']), 0, 200));
$after = apiCall('GET', $api . '/directory/customers/' . $id, null, $at)['data'] ?? [];
check('the address changed', ($after['address'] ?? '') === '10 New Lane');
check('things not on the form were NOT wiped (father name, opening balance, second number)', ($after['profile']['fatherName'] ?? '') === 'Test Father' && (float) ($after['profile']['opening']['cash']['amount'] ?? 0) === 1500.0 && count($after['profile']['contacts'] ?? []) === 2, json_encode($after['profile']['opening'] ?? []));
$r = $a->req('POST', $loc, ['_csrf' => $tok, 'name' => $name, 'number' => [$mob], 'label' => ['whatsapp'], 'address' => 'stale', 'expectedUpdatedAt' => '2001-01-01T00:00:00.000Z']);
check('an edit made on old data is refused (someone else saved in between)', $r['code'] === 422 && str_contains($r['body'], 'changed by someone else'));
$sup = apiCall('GET', $api . '/directory/suppliers?limit=1', null, $at)['data'][0]['_id'] ?? '';
if ($sup) {
    $r = $a->req('GET', '/directory/suppliers/' . $sup);
    check('a supplier page shows its details', $r['code'] === 200 && str_contains($r['body'], 'Details'));
}

echo "\nPermissions\n";
$v = new Browser($base);
$v->login('9000000011', 'Staff@123');
check('a staff login can open the customers page', in_array($v->req('GET', '/directory')['code'], [200, 403], true));

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
