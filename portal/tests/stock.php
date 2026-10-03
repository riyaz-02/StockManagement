<?php
declare(strict_types=1);

/**
 * End-to-end test of the Stock pages against a RUNNING portal and dev API:  php tests/stock.php [http://localhost:8080]
 * Adds ONE test piece to the DEV database and removes it again. Never run against production.
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

echo "Stock list\n";
$r = $a->req('GET', '/stock');
check('the page shows gold and silver in stock and loads the list', $r['code'] === 200 && str_contains($r['body'], 'Gold in stock') && str_contains($r['body'], 'hx-get="/stock/list"'));
$r = $a->req('GET', '/stock/list', [], $HX);
check('the list shows pieces with the total weight', $r['code'] === 200 && str_contains($r['body'], 'net weight') && str_contains($r['body'], 'class="t"'));
check('a whole row opens the piece', str_contains($r['body'], 'data-href="/stock/'));
$r = $a->req('GET', '/stock/list?tab=sold', [], $HX);
check('the Sold tab works', $r['code'] === 200 && (str_contains($r['body'], 'Sold') || str_contains($r['body'], 'No stock found')));
$r = $a->req('GET', '/stock/list?q=zzzz-no-such-piece', [], $HX);
check('a search with no match says so', str_contains($r['body'], 'No stock found'));
$r = $a->req('GET', '/stock/list?metal=silver', [], $HX);
check('the metal filter works', $r['code'] === 200 && !str_contains($r['body'], '>Gold '));

echo "\nAdd, view, edit, remove\n";
$r = $a->req('GET', '/stock/new');
check('the form opens with the shop\'s types, metals and purities', $r['code'] === 200 && str_contains($r['body'], 'name="itemType"') && str_contains($r['body'], '>ring<') && str_contains($r['body'], 'name="purity"') && str_contains($r['body'], 'data-net-calc'));
$r = $post('/stock/calc', ['metalType' => 'gold', 'purity' => '22k', 'netWeight' => '10', 'makingRate' => '100']);
check('the live price is worked out by the server', $r['code'] === 200 && str_contains($r['body'], 'Price with GST') && str_contains($r['body'], 'Metal value'), substr(strip_tags($r['body']), 0, 200));
$r = $post('/stock/calc', ['metalType' => 'gold', 'purity' => '22k']);
check('no weight yet asks for the weight', str_contains($r['body'], 'Enter the weight'));
$r = $a->req('POST', '/stock', ['_csrf' => $tok, 'name' => '', 'itemType' => 'ring', 'metalType' => 'gold', 'purity' => '22k', 'netWeight' => '']);
check('a missing name / weight is refused and the form comes back (422)', $r['code'] === 422 && str_contains($r['body'], 'required fields'));
$name = 'PORTAL TEST piece ' . bin2hex(random_bytes(3));
$r = $a->req('POST', '/stock', ['_csrf' => $tok, 'name' => $name, 'itemType' => 'ring', 'metalType' => 'gold', 'purity' => '22k', 'grossWeight' => '5.2', 'lessWeight' => '0.2', 'netWeight' => '5',
    'numberOfPieces' => '1', 'certificationType' => 'none', 'makingRate' => '150', 'fixedMaking' => '100']);
$loc = $r['headers']['location'] ?? '';
check('saving opens the new piece', $r['code'] === 302 && preg_match('#^/stock/[a-f0-9]{24}$#', $loc) === 1, "($r[code]) " . substr(strip_tags($r['body']), 0, 200));
$r = $a->req('GET', $loc);
check('the piece page shows its details and the making charge for billing (150 x 5 + 100 = 850)', $r['code'] === 200 && str_contains($r['body'], $name) && str_contains($r['body'], '850.00'), substr(strip_tags($r['body']), 0, 300));
check('it shows a price and the Sell and Edit buttons', str_contains($r['body'], 'Price with GST') && str_contains($r['body'], 'Sell (make a bill)') && str_contains($r['body'], '/edit'));
preg_match('#<h1>.*?</h1>#s', $r['body'], $h);
preg_match('#/billing/new\?item=([^"]+)"#', $r['body'], $bm);
$barcode = urldecode($bm[1] ?? '');
$r2 = $a->req('GET', '/billing/new?item=' . rawurlencode($barcode));
check('Sell opens a bill with this piece already on it', str_contains($r2['body'], $name) && str_contains($r2['body'], 'From stock'), $barcode);
$r = $a->req('GET', $loc . '/edit');
check('edit shows the saved values and keeps the fixed making part (100)', $r['code'] === 200 && str_contains($r['body'], 'value="' . $name . '"') && preg_match('/name="fixedMaking" value="100(\.0+)?"/', $r['body']) === 1, substr(strip_tags($r['body']), 0, 200));
$r = $a->req('POST', $loc, ['_csrf' => $tok, 'name' => $name . ' edited', 'itemType' => 'ring', 'metalType' => 'gold', 'purity' => '22k', 'netWeight' => '5', 'grossWeight' => '5.2', 'lessWeight' => '0.2', 'makingRate' => '150', 'fixedMaking' => '100', 'certificationType' => 'none']);
check('saving an edit goes back to the piece', $r['code'] === 302 && ($r['headers']['location'] ?? '') === $loc);
$r = $a->req('GET', $loc);
check('the edit shows and the making charge stayed the same', str_contains($r['body'], 'edited') && str_contains($r['body'], '850.00'));
$r = $post($loc . '/status', ['to' => 'no_sell']);
check('a piece can be marked not for sale', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true');
$r = $a->req('GET', $loc);
check('it then shows "Not for sale" and offers to put it back', str_contains($r['body'], 'Not for sale') && str_contains($r['body'], 'Put back in stock'));
$r = $post($loc . '/status', ['to' => 'active']);
check('and put back in stock', $r['code'] === 204);
$r = $post($loc . '/remove');
check('removing sends the person back to the list', $r['code'] === 204 && ($r['headers']['hx-redirect'] ?? '') === '/stock');
$r = $a->req('GET', '/stock/list?q=' . rawurlencode($name), [], $HX);
check('the removed piece is gone from the list', str_contains($r['body'], 'No stock found'));

echo "\nBulk stock and the stock check\n";
check('the Stock page loads the stock check and the bulk panel', str_contains($a->req('GET', '/stock')['body'], 'hx-get="/stock/check"') && str_contains($a->req('GET', '/stock')['body'], 'hx-get="/stock/bulk"'));
$r = $a->req('GET', '/stock/bulk/new', [], $HX);
check('the add-bulk form offers the kinds (dust, parts, sub items, raw, in process ...) and the metals', $r['code'] === 200 && str_contains($r['body'], 'Dust / filings') && str_contains($r['body'], 'Sub items') && str_contains($r['body'], 'In process') && str_contains($r['body'], 'name="weightGrams"'));
$r = $post('/stock/bulk', ['metalType' => 'gold', 'weightGrams' => '0', 'description' => 'PORTAL TEST bench dust', 'category' => 'dust']);
check('a zero weight is refused inside the form (422)', $r['code'] === 422 && str_contains($r['body'], 'notice-error'), (string) $r['code']);
$r = $post('/stock/bulk', ['metalType' => 'gold', 'weightGrams' => '12.345', 'description' => 'PORTAL TEST bench dust', 'category' => 'dust', 'purity' => '22K', 'pieces' => '']);
check('a bulk entry is added and the lists refresh', $r['code'] === 204 && str_contains($r['headers']['hx-trigger'] ?? '', 'data-changed'), (string) $r['code']);
$r = $a->req('GET', '/stock/bulk', [], $HX);
check('the panel lists it with its kind, weight and purity', $r['code'] === 200 && str_contains($r['body'], 'PORTAL TEST bench dust') && str_contains($r['body'], 'Dust / filings') && str_contains($r['body'], '12.345') && str_contains($r['body'], '22K'));
preg_match('#/stock/bulk/([0-9a-f]{24})/edit#', $r['body'], $mm);
$bid = $mm[1] ?? '';
check('it has an edit and a remove button', $bid !== '' && str_contains($r['body'], "/stock/bulk/$bid/remove"));
$r = $a->req('GET', "/stock/bulk/$bid/edit", [], $HX);
check('the edit form opens with the saved values', $r['code'] === 200 && str_contains($r['body'], 'PORTAL TEST bench dust') && str_contains($r['body'], '12.345'));
$r = $post("/stock/bulk/$bid", ['weightGrams' => '20', 'description' => 'PORTAL TEST bench dust', 'category' => 'parts', 'purity' => '22K', 'pieces' => '40']);
check('it can be changed (weight, kind, pieces)', $r['code'] === 204);
$r = $a->req('GET', '/stock/bulk', [], $HX);
check('the change shows', str_contains($r['body'], 'Parts') && str_contains($r['body'], '40') && str_contains($r['body'], '20 g'), substr(strip_tags($r['body']), 0, 200));
$r = $a->req('GET', '/stock/check', [], $HX);
check('the stock check shows what came in against what is in the shop, for each metal', $r['code'] === 200 && str_contains($r['body'], 'In the shop: bulk stock') && str_contains($r['body'], 'Sold on bills') && str_contains($r['body'], 'Difference') && str_contains($r['body'], 'Gold'));
$r = $post("/stock/bulk/$bid/remove");
check('a bulk entry can be removed', $r['code'] === 204);
check('and is gone from the panel', !str_contains($a->req('GET', '/stock/bulk', [], $HX)['body'], 'PORTAL TEST bench dust'));

echo "\nPermissions\n";
$v = new Browser($base);
$v->login('9000000011', 'Staff@123');
check('a staff login can open the stock list', $v->req('GET', '/stock')['code'] === 200);

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
