<?php
declare(strict_types=1);

/**
 * End-to-end test of the Purchases pages against a RUNNING portal and dev API:  php tests/purchases.php [http://localhost:8080]
 * Adds test purchases to the DEV database and removes them again. Never run against production.
 */
require __DIR__ . '/Browser.php';

$base = rtrim($argv[1] ?? 'http://localhost:8080', '/');
$pass = 0;
$fail = 0;
function check(string $name, bool $ok, string $detail = ''): void
{
    global $pass, $fail;
    if ($ok) { $pass++; echo "  ok    $name\n"; } else { $fail++; echo "  FAIL  $name $detail\n"; }
}
$HX = ['HX-Request: true'];
$a = new Browser($base);
$a->login('7029621489', 'Admin@123');
$tok = $a->csrf('/');
$post = fn (string $path, array $form = []) => $a->req('POST', $path, $form, ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);

echo "Purchases list\n";
$r = $a->req('GET', '/purchases');
check('the page opens and loads its list', $r['code'] === 200 && str_contains($r['body'], 'hx-get="/purchases/list"'));
$r = $a->req('GET', '/purchases/list', [], $HX);
check('the list shows bills, suppliers and the metal totals', $r['code'] === 200 && str_contains($r['body'], 'Gold bought') && str_contains($r['body'], 'class="t"'));
$r = $a->req('GET', '/purchases/list?q=zzzz-no-supplier', [], $HX);
check('a search with no match says so', str_contains($r['body'], 'No purchases found'));
$r = $a->req('GET', '/purchases/list?metal=silver', [], $HX);
check('the metal filter works', $r['code'] === 200 && !str_contains($r['body'], '<td>Gold</td>'));

echo "\nNew purchase\n";
$r = $a->req('GET', '/purchases/new');
check('the form opens with supplier suggestions', $r['code'] === 200 && str_contains($r['body'], 'name="biller"') && str_contains($r['body'], '<datalist id="suppliers">'));
$r = $post('/purchases/calc', ['metalType' => 'gold', 'transactionType' => 'intra-state', 'quantity' => '10', 'rate' => '7000']);
check('weight x rate gives taxable value, CGST/SGST and the credit', $r['code'] === 200 && str_contains($r['body'], '70,000.00') && str_contains($r['body'], 'CGST') && str_contains($r['body'], 'GST claimed back'), substr(strip_tags($r['body']), 0, 200));
$r = $post('/purchases/calc', ['metalType' => 'gold', 'transactionType' => 'inter-state', 'quantity' => '10', 'rate' => '7000']);
check('another state shows IGST', str_contains($r['body'], 'IGST') && !str_contains($r['body'], 'CGST'));
$r = $post('/purchases/calc', ['metalType' => 'gold', 'useValuation' => '1', 'vNet' => '10', 'purity' => '22K', 'vWastage' => '1', 'vRate' => '7000', 'vLabour' => '50']);
check('the valuation rules give an amount too', $r['code'] === 200 && str_contains($r['body'], 'Total payable'), substr(strip_tags($r['body']), 0, 200));
$r = $post('/purchases/calc', ['metalType' => 'gold', 'useValuation' => '1', 'vNet' => '10']);
check('a valuation without a rate is explained in words', str_contains($r['body'], 'weight and the rate'));
$r = $post('/purchases/calc', []);
check('an empty form just asks for the weight', str_contains($r['body'], 'Enter the weight'));

$no = strtoupper('PT-' . bin2hex(random_bytes(4)));
$form = ['_csrf' => $tok, 'biller' => 'PORTAL TEST Supplier', 'billerGstin' => '', 'invoiceNumber' => $no, 'invoiceDate' => date('Y-m-d'), 'metalType' => 'gold', 'transactionType' => 'intra-state', 'quantity' => '10', 'rate' => '7000', 'description' => 'test'];
$r = $a->req('POST', '/purchases', array_merge($form, ['biller' => '']));
check('a missing supplier is refused and the form comes back (422)', $r['code'] === 422 && str_contains($r['body'], 'Missing required') && str_contains($r['body'], $no));
$r = $a->req('POST', '/purchases', $form);
$loc = $r['headers']['location'] ?? '';
check('saving opens the purchase', $r['code'] === 302 && preg_match('#^/purchases/[a-f0-9]{24}$#', $loc) === 1, "($r[code]) " . substr(strip_tags($r['body']), 0, 200));
$r = $a->req('GET', $loc);
check('the page shows the bill, taxable value and credit', $r['code'] === 200 && str_contains($r['body'], $no) && str_contains($r['body'], '70,000.00') && str_contains($r['body'], 'input credit'));
$r = $a->req('POST', '/purchases', $form);
check('the same bill number twice is refused (duplicate)', $r['code'] === 422 && str_contains($r['body'], 'already exists'));
$r = $post($loc . '/remove');
check('a purchase can be removed', $r['code'] === 204 && ($r['headers']['hx-redirect'] ?? '') === '/purchases');
$r = $a->req('GET', '/purchases/list?q=PORTAL%20TEST', [], $HX);
check('the removed purchase is gone from the list', str_contains($r['body'], 'No purchases found'));

echo "\nPermissions\n";
$v = new Browser($base);
$v->login('9000000011', 'Staff@123');
check('a staff login can open the purchases list', in_array($v->req('GET', '/purchases')['code'], [200, 403], true));

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
