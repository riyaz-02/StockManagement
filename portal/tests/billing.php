<?php
declare(strict_types=1);

/**
 * End-to-end test of GST Billing and Estimates pages against a RUNNING portal and a RUNNING dev API:
 *   php tests/billing.php [http://localhost:8080] [http://localhost:5000/api]
 * Creates test bills / estimates in the DEV database. Never run against production.
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
$item = fn (array $o = []) => ['particulars' => 'PORTAL TEST ring', 'metalType' => 'Gold', 'purity' => '22K', 'netWt' => '5', 'makingCharge' => '1000'] + $o;

echo "Bills: list and search\n";
$r = $a->req('GET', '/billing');
check('the page opens and loads the list by itself', $r['code'] === 200 && str_contains($r['body'], 'hx-get="/billing/list"') && str_contains($r['body'], 'New bill'));
$r = $a->req('GET', '/billing/list', [], $HX);
check('the list shows bills with their numbers and status', $r['code'] === 200 && str_contains($r['body'], 'class="t"') && (str_contains($r['body'], 'Paid') || str_contains($r['body'], 'Due')));
$r = $a->req('GET', '/billing/list?q=zzzz-no-such-bill', [], $HX);
check('a search with no match says so', str_contains($r['body'], 'No bills found'));
$r = $a->req('GET', '/billing/list?status=due', [], $HX);
check('the "money due" filter works', $r['code'] === 200 && !str_contains($r['body'], 'pill-green'));

echo "\nNew bill: form, totals by the server\n";
$r = $a->req('GET', '/billing/new');
check('the form opens with today\'s rates, a state list and one empty item', $r['code'] === 200 && str_contains($r['body'], 'name="goldRate"') && str_contains($r['body'], 'West Bengal') && str_contains($r['body'], 'name="items['));
$r = $a->req('GET', '/billing/row', [], $HX);
check('"Add another item" gives a new empty row', $r['code'] === 200 && str_contains($r['body'], '[particulars]') && str_contains($r['body'], 'data-remove-row'));
$r = $post('/billing/calc', ['goldRate' => '9000', 'silverRate' => '100', 'placeOfSupply' => '19-West Bengal', 'items' => ['a' => $item()], 'payments' => [['mode' => 'Cash', 'amount' => '1000']]]);
check('the total box shows taxable value, CGST/SGST, total and what stays due', $r['code'] === 200 && str_contains($r['body'], 'CGST 1.5%') && str_contains($r['body'], 'Bill total') && str_contains($r['body'], 'Will stay due'), substr($r['body'], 0, 200));
$r = $post('/billing/calc', ['goldRate' => '9000', 'placeOfSupply' => '19-West Bengal', 'items' => ['a' => ['particulars' => 'PORTAL TEST earring', 'metalType' => 'Gold', 'netWt' => '2', 'rate' => '1000', 'makingCharge' => '100', 'certification' => 'hallmark', 'hallmarkCharge' => '45']]]);
check('a hallmark fee has its own "no GST" row: taxable 2,100, total 2,208 (the fee is not taxed again)', $r['code'] === 200 && str_contains($r['body'], 'Hallmark / HUID fee (no GST)') && str_contains($r['body'], '2,100') && str_contains($r['body'], '2,208') && !str_contains($r['body'], '2,145'), substr(strip_tags($r['body']), 0, 300));
$r = $post('/billing/calc', ['goldRate' => '9000', 'placeOfSupply' => '27-Maharashtra', 'items' => ['a' => $item()]]);
check('another state shows IGST', str_contains($r['body'], 'IGST 3%') && !str_contains($r['body'], 'CGST 1.5%'));
$r = $post('/billing/calc', ['goldRate' => '9000', 'items' => ['a' => $item(['netWt' => '5', 'grossWt' => '2'])]]);
check('a wrong item is explained in words (net more than gross)', str_contains($r['body'], 'net weight cannot be more than gross'));
$r = $post('/billing/calc', ['goldRate' => '9000', 'items' => ['a' => ['particulars' => '', 'netWt' => '']]]);
check('an empty form just asks for an item', str_contains($r['body'], 'Add an item'));
$r = $post('/billing/calc', ['goldRate' => '9000', 'items' => ['a' => $item(['makingCharge' => '0'])], 'discount' => '5000']);
check('a discount above what is allowed is refused with the limit', str_contains($r['body'], 'No discount is possible') || str_contains($r['body'], 'too high'), substr(strip_tags($r['body']), 0, 300));

echo "\nNew bill: stock pieces and old metal\n";
$r = $a->req('GET', '/billing/stock-row?code=NO-SUCH-CODE-1', [], $HX);
check('an unknown barcode gives a message, not an error page', $r['code'] === 204 && str_contains($r['headers']['hx-trigger'] ?? '', 'Item not found'));
$login = apiCall('POST', $api . '/auth/login', ['mobile' => '7029621489', 'password' => 'Admin@123']);
$at = $login['token'] ?? ($login['data']['token'] ?? '');
$items = apiCall('GET', $api . '/items?limit=20&status=active', null, $at);
$rows = $items['data']['items'] ?? ($items['data'] ?? []);
$code = '';
foreach ((array) $rows as $it) { if (!empty($it['barcode']) && ($it['status'] ?? '') === 'active' && (float) ($it['netWeight'] ?? 0) > 0) { $code = $it['barcode']; break; } }
if ($code !== '') {
    $r = $a->req('GET', '/billing/stock-row?code=' . rawurlencode($code) . '&goldRate=9000&silverRate=100', [], $HX);
    check('a real barcode gives a filled row (name, weight, making) marked "From stock"', $r['code'] === 200 && str_contains($r['body'], 'From stock') && preg_match('/\[netWt\]" value="[0-9.]+"/', $r['body']) === 1);
} else {
    echo "  skip  no active stock piece in the dev data\n";
}
$r = $a->req('GET', '/billing/old-metal?customerName=zz', [], $HX);
check('old metal panel: too short a name says how to add some', $r['code'] === 200 && str_contains($r['body'], 'No unused old metal'));

$r = $a->req('GET', '/billing/stock-search?code=Gold', [], $HX);
check('the stock search under the item box lists matching pieces (name, barcode, metal, weight)', $r['code'] === 200 && (str_contains($r['body'], 'data-hit') || str_contains($r['body'], 'No stock piece matches')) && str_contains($r['body'], 'g<'));
$r = $a->req('GET', '/billing/stock-search?code=zzzz-none', [], $HX);
check('a search with no match explains it and offers the exact-barcode Enter', str_contains($r['body'], 'No stock piece matches'));
$r = $a->req('GET', '/billing/cash-room?mobile=9000000099');
check('the cash room for a customer is a small JSON answer (s.269ST)', $r['code'] === 200 && str_contains($r['headers']['content-type'] ?? '', 'json') && isset(json_decode($r['body'], true)['room']));
$r = $a->req('GET', '/billing/new');
check('the form carries the checks the app has (PAN, HUID, cash limit, address) and the instant-calculation scripts', str_contains($r['body'], 'billing-calc.js') && str_contains($r['body'], 'bill.js') && str_contains($r['body'], 'data-cash-limit') && str_contains($r['body'], 'id="final-amount"') && str_contains($r['body'], 'data-round="100"'));
check('the browser copy of the billing engine is the server engine (no drift)', (int) shell_exec('cd ' . escapeshellarg(dirname(__DIR__, 2) . '/backend') . ' && node scripts/gen-portal-calc.js --check > NUL 2>&1 && echo 1 || echo 0') === 1);

echo "\nNew bill: saving\n";
$rid = 'inv-portaltest-' . bin2hex(random_bytes(6));
$form = ['rid' => $rid, 'mode' => 'bill', 'customerName' => 'PORTAL TEST Buyer', 'customerMobile' => '9000000099', 'customerAddress' => '1 Test Road, Howrah', 'invoiceDate' => date('Y-m-d'),
    'goldRate' => '9000', 'silverRate' => '100', 'placeOfSupply' => '19-West Bengal', 'items' => ['a' => $item()], 'payments' => [['mode' => 'Cash', 'amount' => '1000'], ['mode' => 'Online', 'amount' => '']]];
$r = $a->req('POST', '/billing', $form + ['_csrf' => $tok]);
check('a walk-in bill left partly unpaid is refused and the form comes back with what was typed', $r['code'] === 422 && str_contains($r['body'], 'paid in full') && str_contains($r['body'], 'PORTAL TEST Buyer') && str_contains($r['body'], 'PORTAL TEST ring'));
$calc = apiCall('POST', $api . '/billing/calculate', ['items' => [$item()], 'goldRate' => 9000, 'placeOfSupply' => '19-West Bengal'], $at);
$payable = (float) ($calc['data']['totalPayableAmount'] ?? 0);
$form['payments'][0]['amount'] = (string) $payable;
$form['payments'][0]['mode'] = 'Online';   // cash from one person is capped per day (s.269ST), so test bills are paid online
$r = $a->req('POST', '/billing', $form + ['_csrf' => $tok]);
$loc = $r['headers']['location'] ?? '';
check('a fully paid bill is saved and opens its page', $r['code'] === 302 && preg_match('#^/billing/[a-f0-9]{24}$#', $loc) === 1, "($r[code]) $loc " . substr($r['body'], 0, 200));
$again = $a->req('POST', '/billing', $form + ['_csrf' => $tok]);
check('sending the same form twice does not make a second bill (same request id)', ($again['headers']['location'] ?? '') === $loc, ($again['headers']['location'] ?? '') . ' vs ' . $loc);
$r = $a->req('GET', $loc);
check('the bill page shows customer, items, totals and the payment', $r['code'] === 200 && str_contains($r['body'], 'PORTAL TEST Buyer') && str_contains($r['body'], 'PORTAL TEST ring') && str_contains($r['body'], 'Bill total') && str_contains($r['body'], 'Payments'));
check('the saved message is shown on it', str_contains($r['body'], 'saved'));
$id = substr($loc, strlen('/billing/'));
$r = $a->req('GET', $loc . '/print');
check('the print page is the tax invoice (ORIGINAL first)', $r['code'] === 200 && str_contains($r['body'], 'TAX INVOICE') && str_contains($r['body'], 'ORIGINAL') && str_contains($r['body'], 'GSTIN'));
$r = $a->req('GET', $loc . '/print');
check('printing again says DUPLICATE', str_contains($r['body'], 'DUPLICATE'));

echo "\nReturns and refunds\n";
$r = $a->req('GET', $loc . '/return', [], $HX);
check('the return form lists the bill\'s items', $r['code'] === 200 && str_contains($r['body'], 'PORTAL TEST ring') && str_contains($r['body'], 'name="ret[0][on]"'));
$r = $post($loc . '/return/preview', ['ret' => [0 => ['on' => '1', 'taxable' => '1000']]]);
check('the credit note total is worked out by the server', $r['code'] === 200 && str_contains($r['body'], 'Credit note total'));
$r = $post($loc . '/return', ['rid' => 'cn-portaltest-' . bin2hex(random_bytes(5)), 'ret' => [0 => ['on' => '1', 'taxable' => '1000']], 'reason' => 'sales_return', 'refundMode' => 'Cash', 'refundAmount' => '500', 'restock' => '1']);
check('saving a part return refreshes the page', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true', "($r[code]) " . substr($r['body'], 0, 200));
$r = $a->req('GET', $loc);
check('the bill page lists the credit note', str_contains($r['body'], 'Credit notes') && str_contains($r['body'], 'CN-'));

echo "\nEstimates\n";
$r = $a->req('GET', '/estimates/list', [], $HX);
check('the list opens', $r['code'] === 200 && (str_contains($r['body'], 'class="t"') || str_contains($r['body'], 'No estimates')));
$r = $a->req('GET', '/estimates/new');
check('the estimate form is the bill form without payment (and with validity)', $r['code'] === 200 && str_contains($r['body'], 'Valid for (days)') && !str_contains($r['body'], 'name="payments['));
$er = ['rid' => 'est-portaltest-' . bin2hex(random_bytes(5)), 'mode' => 'estimate', 'customerName' => 'PORTAL TEST Quote', 'customerMobile' => '9000000098', 'goldRate' => '9000', 'silverRate' => '100', 'items' => ['a' => $item()], 'validDays' => '7'];
$r = $a->req('POST', '/estimates', $er + ['_csrf' => $tok]);
$eloc = $r['headers']['location'] ?? '';
check('saving an estimate opens it', $r['code'] === 302 && preg_match('#^/estimates/[a-f0-9]{24}$#', $eloc) === 1, "($r[code]) " . substr($r['body'], 0, 200));
$r = $a->req('GET', $eloc);
check('the estimate page shows items, total and "Make the bill"', str_contains($r['body'], 'PORTAL TEST ring') && str_contains($r['body'], 'Estimate total') && str_contains($r['body'], 'Make the bill'));
$eid = substr($eloc, strlen('/estimates/'));
$r = $a->req('GET', '/billing/new?estimate=' . $eid);
check('"Make the bill" pre-fills customer and items from the estimate', str_contains($r['body'], 'PORTAL TEST Quote') && str_contains($r['body'], 'PORTAL TEST ring') && str_contains($r['body'], 'name="estimateId"'));
$r = $a->req('GET', $eloc . '/print');
check('the estimate prints as NOT A TAX INVOICE', str_contains($r['body'], 'NOT A TAX INVOICE'));
$r = $a->req('DELETE', $eloc, [], ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);
check('an open estimate can be cancelled', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true', "($r[code])");

echo "\nDelivering an order\n";
$r = $a->req('GET', '/billing/new?order=000000000000000000000000');
check('a missing order does not break the form', $r['code'] === 200 && !str_contains($r['body'], 'name="orderId"'));

echo "\nPermissions\n";
$v = new Browser($base);
$v->login('9000000011', 'Staff@123');
check('a staff login can open the bill list', $v->req('GET', '/billing')['code'] === 200);

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
