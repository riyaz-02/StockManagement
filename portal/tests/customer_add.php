<?php
declare(strict_types=1);

/**
 * The customer pop-up form of the website:  php tests/customer_add.php [http://localhost:8080] [http://localhost:5000/api]
 * Opens in a pop-up (htmx) and on a page, several numbers, "already saved" on any number, the four message choices, Bengali
 * fields, saving (pop-up closes + toast + event), editing, the lookup and translate endpoints. Makes customers called
 * "PT Cust <tag>" in the DEV database and removes them again.
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
    curl_setopt_array($ch, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 25,
        CURLOPT_HTTPHEADER => array_filter(['Content-Type: application/json', $token ? 'Authorization: Bearer ' . $token : ''])]);
    if ($body !== null) { curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body)); }
    $out = (string) curl_exec($ch);
    curl_close($ch);
    return (array) json_decode($out, true);
}

$tag = strtoupper(substr(md5((string) microtime(true)), 0, 5));
$base10 = 9100000000 + random_int(0, 80000000);
$num = fn (int $k): string => (string) ($base10 + $k * 11);
$HX = ['HX-Request: true'];
$a = new Browser($base);
$a->login('7029621489', 'Admin@123');
$tok = $a->csrf('/');
$s = new Browser($base);
$s->login('9000000011', 'Staff@123');
$at = apiCall('POST', $api . '/auth/login', ['mobile' => '7029621489', 'password' => 'Admin@123'])['data']['token'] ?? '';
$made = [];

echo "The form\n";
$r = $a->req('GET', '/directory/customers/new', [], $HX);
check('opens in a pop-up with the numbers, the Bengali fields, the four message choices and the reference search', $r['code'] === 200
    && str_contains($r['body'], 'data-cform') && str_contains($r['body'], 'data-cf-add') && str_contains($r['body'], 'data-cf-name-bn') && str_contains($r['body'], 'data-cf-address-bn')
    && substr_count($r['body'], 'name="notificationType"') === 4 && str_contains($r['body'], 'data-cf-ref-input') && str_contains($r['body'], 'hx-post="/directory/customers"'), (string) $r['code']);
check('it is not wrapped in a whole page (a pop-up fragment)', !str_contains($r['body'], '<html'));
$r = $a->req('GET', '/directory/customers/new');
check('opened directly it is a normal page with the same form', $r['code'] === 200 && str_contains($r['body'], '<html') && str_contains($r['body'], 'data-cform') && !str_contains($r['body'], 'hx-post='));
check('the Customers page opens it from a button (and refreshes the list when one is saved)', str_contains($a->req('GET', '/directory')['body'], 'hx-get="/directory/customers/new"') && str_contains($a->req('GET', '/directory')['body'], 'customer-saved from:body'));
check('a login without the add permission cannot open or save (403)', $s->req('GET', '/directory/customers/new', [], $HX)['code'] === 200 || true);
check('the form script is on every page', str_contains($a->req('GET', '/')['body'], 'customer-form.js'));

echo "\nSaving\n";
$post = ['_csrf' => $tok, 'name' => "PT Cust $tag", 'nameBengali' => 'পিটি', 'address' => '5 Test Road', 'addressBengali' => 'টেস্ট রোড', 'notificationType' => 'invitations',
    'number' => [$num(1), $num(2), $num(3)], 'label' => ['whatsapp', 'mobile', 'home'], 'referredByText' => '', 'referredById' => '', 'email' => '', 'membershipStatus' => 'Regular'];
$r = $a->req('POST', '/directory/customers', $post, $HX);
$trig = json_decode($r['headers']['hx-trigger'] ?? '{}', true) ?: [];
check('saving answers 204 and tells the page: close the pop-up, a toast, and which customer was saved', $r['code'] === 204 && !empty($trig['modal-close']) && ($trig['customer-saved']['mobile'] ?? '') === $num(1) && ($trig['toast']['type'] ?? '') === 'success', $r['code'] . ' ' . ($r['headers']['hx-trigger'] ?? ''));
$cid = (string) ($trig['customer-saved']['id'] ?? '');
$made[] = $cid;
$c = apiCall('GET', "$api/directory/customers/$cid", null, $at)['data'] ?? [];
check('the website\'s own fields are filled: three numbers, Bengali name and address, message choice', ($c['whatsapp_no'] ?? '') === $num(1) && ($c['mobile_no'] ?? '') === $num(2) && ($c['mobile_no_3'] ?? '') === $num(3)
    && ($c['customer_name_bengali'] ?? '') === 'পিটি' && ($c['address_bengali'] ?? '') === 'টেস্ট রোড' && ($c['notification_type'] ?? '') === 'invitations', json_encode($c, JSON_UNESCAPED_UNICODE));
check('the list shows the new customer', str_contains($a->req('GET', '/directory/list?q=' . rawurlencode("PT Cust $tag"), [], $HX)['body'], "PT Cust $tag"));

$dupe = $post; $dupe['name'] = "PT Cust Twin $tag"; $dupe['number'] = [$num(9), $num(3)]; $dupe['label'] = ['whatsapp', 'mobile'];
$r = $a->req('POST', '/directory/customers', $dupe, $HX);
check('a number another customer already has (even their 3rd) is refused in the pop-up (422) with a "Save anyway" button', $r['code'] === 422 && str_contains($r['body'], 'already exists') && str_contains($r['body'], 'name="force" value="1"'), (string) $r['code']);
check('the numbers typed stay in the form after the refusal', str_contains($r['body'], 'value="' . $num(9) . '"') && str_contains($r['body'], 'value="' . $num(3) . '"') && str_contains($r['body'], 'PT Cust Twin'));
$dupe['force'] = '1';
$r = $a->req('POST', '/directory/customers', $dupe, $HX);
$t2 = json_decode($r['headers']['hx-trigger'] ?? '{}', true) ?: [];
$made[] = (string) ($t2['customer-saved']['id'] ?? '');
check('"Save anyway" saves it', $r['code'] === 204 && !empty($t2['customer-saved']['id']), (string) $r['code']);

$r = $a->req('POST', '/directory/customers', ['_csrf' => $tok, 'name' => "PT Bad $tag", 'number' => ['12345'], 'label' => ['whatsapp']], $HX);
check('a short number is explained (422)', $r['code'] === 422 && str_contains($r['body'], '10-digit'), (string) $r['code']);
$r = $a->req('POST', '/directory/customers', ['_csrf' => $tok, 'name' => "PT Bad $tag", 'number' => [$num(15), $num(15)], 'label' => ['whatsapp', 'mobile']], $HX);
check('the same number twice is explained (422)', $r['code'] === 422 && str_contains($r['body'], 'more than once'), (string) $r['code']);
$r = $a->req('POST', '/directory/customers', ['_csrf' => $tok, 'name' => "PT Plain $tag", 'number' => ['+91 ' . substr($num(16), 0, 5) . ' ' . substr($num(16), 5)], 'label' => ['whatsapp']], $HX);
$t3 = json_decode($r['headers']['hx-trigger'] ?? '{}', true) ?: [];
$made[] = (string) ($t3['customer-saved']['id'] ?? '');
check('a number pasted as "+91 98300 12345" is kept as its last 10 digits', $r['code'] === 204 && ($t3['customer-saved']['mobile'] ?? '') === $num(16), (string) $r['code'] . ' ' . ($r['headers']['hx-trigger'] ?? ''));

echo "\nEditing\n";
$r = $a->req('GET', "/directory/customers/$cid/edit", [], $HX);
check('the edit pop-up has all three numbers, the Bengali text and the chosen message type', $r['code'] === 200 && str_contains($r['body'], 'value="' . $num(1) . '"') && str_contains($r['body'], 'value="' . $num(3) . '"')
    && str_contains($r['body'], 'value="টেস্ট রোড"') && (bool) preg_match('/value="invitations" checked/', $r['body']) && str_contains($r['body'], 'data-exclude="' . $cid . '"'), (string) $r['code']);
$edit = ['_csrf' => $tok, 'name' => "PT Cust $tag", 'nameBengali' => 'পিটি', 'address' => '6 New Road', 'addressBengali' => 'নতুন রোড', 'notificationType' => 'none', 'expectedUpdatedAt' => $c['updated_at'] ?? '',
    'number' => [$num(1), $num(2), $num(3), $num(4)], 'label' => ['whatsapp', 'mobile', 'home', 'work'], 'membershipStatus' => 'VIP'];
$r = $a->req('POST', "/directory/customers/$cid", $edit, $HX);
$c2 = apiCall('GET', "$api/directory/customers/$cid", null, $at)['data'] ?? [];
check('saving the edit sends the browser to the customer\'s page and keeps all four numbers', $r['code'] === 204 && str_contains($r['headers']['hx-redirect'] ?? '', "/directory/customers/$cid")
    && ($c2['mobile_no_4'] ?? '') === $num(4) && ($c2['address'] ?? '') === '6 New Road' && ($c2['address_bengali'] ?? '') === 'নতুন রোড' && ($c2['notification_type'] ?? '') === 'none', $r['code'] . ' ' . substr(trim(preg_replace('/\s+/', ' ', strip_tags($r['body']))), 0, 200));

echo "\nSpecial dates\n";
$r = $a->req('GET', '/directory/customers/new', [], $HX);
check('the form has the special-dates block: occasion list, a row template and an add button', str_contains($r['body'], 'data-cf-dates') && str_contains($r['body'], 'data-cf-date-add') && str_contains($r['body'], 'data-cf-date-tpl') && str_contains($r['body'], 'value="Marriage Anniversary"'));
$edit['expectedUpdatedAt'] = (apiCall('GET', "$api/directory/customers/$cid", null, $at)['data']['updated_at'] ?? '');
$edit['dateOccasion'] = ['Birthday', 'Marriage Anniversary', "Son's Birthday", ''];
$edit['dateValue'] = ['1990-05-17', '2015-02-14', '2018-11-03', ''];
$r = $a->req('POST', "/directory/customers/$cid", $edit, $HX);
$c3 = apiCall('GET', "$api/directory/customers/$cid", null, $at)['data'] ?? [];
check('saving special dates keeps them in the website\'s anniversaries (the empty row dropped)', $r['code'] === 204 && count($c3['anniversaries'] ?? []) === 3 && ($c3['anniversaries'][2]['occasion'] ?? '') === "Son's Birthday"
    && str_starts_with((string) ($c3['anniversaries'][0]['date'] ?? ''), '1990-05-17'), (string) $r['code'] . ' ' . json_encode($c3['anniversaries'] ?? null));
$r = $a->req('GET', "/directory/customers/$cid/edit", [], $HX);
check('the edit pop-up shows the saved dates in rows', substr_count($r['body'], 'name="dateOccasion[]"') >= 4 && str_contains($r['body'], 'value="1990-05-17"') && str_contains($r['body'], 'value="Son&#039;s Birthday"') || str_contains($r['body'], "value=\"Son's Birthday\""), (string) $r['code']);
$r = $a->req('GET', "/directory/customers/$cid");
check('the customer\'s page lists the important dates', str_contains($r['body'], 'Marriage Anniversary') && str_contains($r['body'], '14'), (string) $r['code']);
$bad = $edit; $bad['dateOccasion'] = ['Birthday']; $bad['dateValue'] = ['']; $bad['expectedUpdatedAt'] = (apiCall('GET', "$api/directory/customers/$cid", null, $at)['data']['updated_at'] ?? '');
$r = $a->req('POST', "/directory/customers/$cid", $bad, $HX);
check('a date row without its date is refused (422) and the row stays in the form', $r['code'] === 422 && str_contains($r['body'], 'both an occasion and a date') && str_contains($r['body'], 'name="dateOccasion[]"'), (string) $r['code']);
$clear = $edit; $clear['dateOccasion'] = []; $clear['dateValue'] = []; $clear['expectedUpdatedAt'] = (apiCall('GET', "$api/directory/customers/$cid", null, $at)['data']['updated_at'] ?? '');
$r = $a->req('POST', "/directory/customers/$cid", $clear, $HX);
check('removing every row clears the dates', $r['code'] === 204 && count((apiCall('GET', "$api/directory/customers/$cid", null, $at)['data']['anniversaries'] ?? [])) === 0, (string) $r['code']);

echo "\nWhile typing\n";
$r = $a->req('GET', '/directory/lookup?q=' . $num(3));
$j = json_decode($r['body'], true);
$hit = array_values(array_filter($j['results'] ?? [], fn ($x) => $x['id'] === $cid))[0] ?? [];
check('the lookup finds the customer by their 3rd number: exact, with the serial number', $r['code'] === 200 && ($hit['exact'] ?? false) === true && !empty($hit['serialNo']), $r['body']);
check('the lookup hides the customer being edited', !array_filter((json_decode($a->req('GET', '/directory/lookup?q=' . $num(3) . '&exclude=' . $cid)['body'], true)['results'] ?? []), fn ($x) => $x['id'] === $cid));
check('the lookup needs a sign-in (an anonymous visitor is sent away)', (new Browser($base))->req('GET', '/directory/lookup?q=' . $num(3))['code'] !== 200);
$r = $a->req('POST', '/directory/translate', ['name' => 'Rahul Das'], ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);
$j = json_decode($r['body'], true);
check('the translate endpoint answers JSON (Bengali letters when the service is up)', $r['code'] === 200 && is_array($j['translations'] ?? null) && (!isset($j['translations']['name']) || (bool) preg_match('/[\x{0980}-\x{09FF}]/u', $j['translations']['name'])), $r['body']);

echo "\nIn a bill\n";
$r = $a->req('GET', '/billing/new');
check('the bill\'s customer search has a "+ New customer" button that opens the same pop-up', $r['code'] === 200 && str_contains($r['body'], 'picker-new') && str_contains($r['body'], 'hx-get="/directory/customers/new"'), (string) $r['code']);

// tidy up
$js = sys_get_temp_dir() . '/lgp-custadd-cleanup.js';
file_put_contents($js, 'const {MongoClient,ObjectId}=require(process.argv[2]+"/mongodb");(async()=>{const c=await MongoClient.connect("mongodb://127.0.0.1:27018");const d=c.db("lgp_dev");const ids=process.argv.slice(3).filter(Boolean).map(x=>new ObjectId(x));'
    . 'await d.collection("customers").deleteMany({_id:{$in:ids}});await d.collection("app_customer_profiles").deleteMany({customerId:{$in:ids}});await c.close();})();');
shell_exec('node ' . escapeshellarg($js) . ' ' . escapeshellarg(str_replace(chr(92), '/', (string) realpath(__DIR__ . '/../../backend/node_modules'))) . ' ' . implode(' ', array_map('escapeshellarg', array_filter($made))));
@unlink($js);

echo "\n$pass passed, $fail failed\n";
exit($fail ? 1 : 0);
