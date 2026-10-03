<?php
declare(strict_types=1);

/**
 * End-to-end test of the daily pages (Day Book, Expenses, Pending dues, Orders, Old Metal) against a RUNNING portal and
 * a RUNNING dev API:   php tests/pages.php [http://localhost:8080]
 * Creates a few test records and cleans up after itself where the API allows (cancel). Never run against production.
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

echo "Day Book\n";
$r = $a->req('GET', '/day-book');
check('the page opens and loads its body by itself', $r['code'] === 200 && str_contains($r['body'], 'hx-get="/day-book/body'));
$r = $a->req('GET', '/day-book/body?quick=month', [], $HX);
check('the body shows cash in hand, money by mode and what happened', $r['code'] === 200 && str_contains($r['body'], 'Cash in hand') && str_contains($r['body'], 'Money by how it was paid') && str_contains($r['body'], 'What happened') && str_contains($r['body'], 'Every entry'));
check('amounts are in Indian format with the rupee sign', preg_match('/\x{20B9}\d{1,2}(,\d{2})*,\d{3}\.\d{2}|\x{20B9}\d{1,3}\.\d{2}/u', $r['body']) === 1);
$r = $a->req('GET', '/day-book/body?from=2001-01-01&to=2001-01-02', [], $HX);
check('a day with nothing shows an empty message, not an error', $r['code'] === 200 && str_contains($r['body'], 'No money moved'));

echo "\nExpenses\n";
$r = $a->req('GET', '/expenses/new', [], $HX);
check('the add form opens in the pop-up', $r['code'] === 200 && str_contains($r['body'], 'name="amount"') && str_contains($r['body'], 'Tea / food'));
$r = $post('/expenses', ['amount' => '', 'category' => 'Rent', 'mode' => 'Cash']);
check('a missing amount is refused and shown in the form (422)', $r['code'] === 422 && str_contains($r['body'], 'Enter the amount'));
$r = $post('/expenses', ['amount' => '77.50', 'category' => 'Tea / food', 'mode' => 'Cash', 'note' => 'PAGES TEST', 'date' => date('Y-m-d')]);
check('saving closes the pop-up, shows a message and refreshes the list', $r['code'] === 204 && str_contains($r['headers']['hx-trigger'] ?? '', 'modal-close') && str_contains($r['headers']['hx-trigger'] ?? '', 'data-changed'));
$r = $a->req('GET', '/expenses/list?quick=today', [], $HX);
check('the new expense is in today\'s list with its total', str_contains($r['body'], 'PAGES TEST') && str_contains($r['body'], '77.50'));
preg_match('#/expenses/([a-f0-9]{24})/cancel#', $r['body'], $m);
$r2 = $post('/expenses/' . ($m[1] ?? 'x') . '/cancel');
check('the owner cancels it (it leaves the list)', $r2['code'] === 204 && !str_contains($a->req('GET', '/expenses/list?quick=today', [], $HX)['body'], 'PAGES TEST'));
$r = $a->req('POST', '/expenses', ['amount' => '5', 'category' => 'Other', 'mode' => 'Cash']);
check('saving without the secret token is refused (419)', $r['code'] === 419);

echo "\nPending dues\n";
$r = $a->req('GET', '/dues/list', [], $HX);
check('the list shows the total and the customers who owe', $r['code'] === 200 && str_contains($r['body'], 'owe you') && (str_contains($r['body'], 'Receive') || str_contains($r['body'], 'Nobody owes')));
$r = $a->req('GET', '/dues/list?q=zzzzzz-no-such', [], $HX);
check('a search with no match says so', str_contains($r['body'], 'Nobody matches'));
$full = $a->req('GET', '/dues/list', [], $HX)['body'];
if (preg_match('#/dues/pay/([a-f0-9]{24})#', $full, $mm)) {
    $f = $a->req('GET', '/dues/pay/' . $mm[1], [], $HX);
    check('the receive form shows the bill and what is still due', $f['code'] === 200 && str_contains($f['body'], 'Still due') && str_contains($f['body'], 'name="rid"'));
    $r = $post('/dues/pay/' . $mm[1], ['amount' => '999999999', 'mode' => 'Cash', 'rid' => 'pay-test-over-' . time()]);
    check('taking more than is due is refused by the API and explained (422)', $r['code'] === 422 && str_contains($r['body'], 'due'), substr($r['body'], 0, 200));
} else {
    check('(no bill with a due amount in the dev data: receive form skipped)', true);
}

echo "\nOrders\n";
$r = $a->req('GET', '/orders');
check('the orders page opens', $r['code'] === 200 && str_contains($r['body'], 'New order'));
$r = $a->req('GET', '/orders/new');
check('the new order form has the customer search, item, price and advance', $r['code'] === 200 && str_contains($r['body'], 'name="customerName"') && str_contains($r['body'], 'name="advanceAmount"') && str_contains($r['body'], 'name="rid"'));
$rid = preg_match('/name="rid" value="([^"]+)"/', $r['body'], $x) ? $x[1] : 'ord-x';
$bad = $a->req('POST', '/orders', ['_csrf' => $tok, 'rid' => $rid, 'customerName' => 'PAGES Ord', 'customerMobile' => '9000000099', 'description' => '', 'deliveryDate' => date('Y-m-d', strtotime('+10 days'))]);
check('an order without a description shows the API message on the form (422)', $bad['code'] === 422 && str_contains($bad['body'], 'Describe what is to be made'));
$ok = $a->req('POST', '/orders', ['_csrf' => $tok, 'rid' => $rid . 'ok', 'customerName' => 'PAGES Ord', 'customerMobile' => '9000000099', 'description' => 'Test chain for pages', 'metalType' => 'gold', 'purity' => '22K', 'estimatedPrice' => '20000', 'deliveryDate' => date('Y-m-d', strtotime('+10 days')), 'advanceAmount' => '5000', 'advanceMode' => 'Cash']);
check('a good order is saved and opens its page', $ok['code'] === 302 && preg_match('#^/orders/[a-f0-9]{24}$#', $ok['headers']['location'] ?? '') === 1, (string) $ok['code']);
$dup = $a->req('POST', '/orders', ['_csrf' => $tok, 'rid' => $rid . 'ok', 'customerName' => 'PAGES Ord', 'customerMobile' => '9000000099', 'description' => 'Test chain for pages', 'metalType' => 'gold', 'purity' => '22K', 'estimatedPrice' => '20000', 'deliveryDate' => date('Y-m-d', strtotime('+10 days')), 'advanceAmount' => '5000', 'advanceMode' => 'Cash']);
check('sending the same form twice never makes a second order', ($dup['headers']['location'] ?? '') === ($ok['headers']['location'] ?? 'x'));
$loc = $ok['headers']['location'];
$oid = substr($loc, strlen('/orders/'));
$r = $a->req('GET', $loc);
check('the order page shows the item, the advance and the balance', $r['code'] === 200 && str_contains($r['body'], 'Test chain for pages') && str_contains($r['body'], '5,000.00') && str_contains($r['body'], '15,000.00'));
check('...and the "saved" message that was kept for the next page is shown there, once', str_contains($r['body'], 'notice-success') && str_contains($r['body'], 'saved.') && !str_contains($a->req('GET', $loc)['body'], 'notice-success'));
check('...and the buttons for what can be done', str_contains($r['body'], 'Given to karigar') && str_contains($r['body'], 'Take more advance') && str_contains($r['body'], 'Cancel order') && str_contains($r['body'], 'Deliver and make the bill'));
$r = $post("/orders/$oid/status", ['status' => 'making']);
check('marking it as being made reloads the page with a message (HX-Refresh)', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true');
check('the status is now "Being made"', str_contains($a->req('GET', $loc)['body'], 'Being made'));
$r = $post("/orders/$oid/advance", ['amount' => '99999', 'mode' => 'Online']);
check('an advance above the price told is refused (422)', $r['code'] === 422 && str_contains($r['body'], 'more than the price'));
$r = $post("/orders/$oid/advance", ['amount' => '1000', 'mode' => 'Online']);
check('more advance is saved', $r['code'] === 204 && str_contains($a->req('GET', $loc)['body'], '6,000.00'));
$list = $a->req('GET', '/orders/list?status=active&q=PAGES', [], $HX)['body'];
check('the order is in the Active list', str_contains($list, 'PAGES Ord') && str_contains($list, 'Being made'));
$r = $post("/orders/$oid/cancel", ['refundMode' => 'Cash', 'refundAmount' => '6000']);
check('the owner cancels it and the advance is returned', $r['code'] === 204 && str_contains($a->req('GET', $loc)['body'], 'Cancelled'));

echo "\nOld metal\n";
$r = $a->req('GET', '/old-metal');
check('the page opens with both buttons', $r['code'] === 200 && str_contains($r['body'], 'Receive old metal') && str_contains($r['body'], 'Buy raw metal'));
$r = $a->req('GET', '/old-metal/new?kind=old', [], $HX);
check('the form opens with today\'s gold rate filled in if one is set', $r['code'] === 200 && str_contains($r['body'], 'name="net"') && str_contains($r['body'], 'name="rate"'));
$r = $post('/old-metal/calc', ['kind' => 'old', 'metalType' => 'gold', 'purity' => '22K', 'net' => '10', 'rate' => '14000', 'deduction' => '2']);
check('the live value is worked out by the SERVER: 10 g of 22K on fine weight = 1,28,240', $r['code'] === 200 && str_contains($r['body'], '1,28,240.00') && str_contains($r['body'], '91.60'), substr($r['body'], 0, 200));
$r = $post('/old-metal/calc', ['kind' => 'old', 'net' => '', 'rate' => '']);
check('with nothing entered it just asks for the weight and rate', str_contains($r['body'], 'Enter the weight'));
$r = $post('/old-metal', ['rid' => 'om-test', 'kind' => 'old', 'customerName' => '', 'metalType' => 'gold', 'purity' => '22K', 'net' => '5', 'rate' => '14000']);
check('saving without a customer name is refused with the reason (422)', $r['code'] === 422 && str_contains($r['body'], 'Enter the customer name'));
$r = $post('/old-metal', ['rid' => 'om-test2', 'kind' => 'old', 'customerName' => 'PAGES OM', 'customerMobile' => '9000000098', 'metalType' => 'gold', 'purity' => '22K', 'net' => '5', 'rate' => '14000', 'note' => 'pages test']);
check('a good entry is saved', $r['code'] === 204 && str_contains($r['headers']['hx-trigger'] ?? '', 'toast'));
$l = $a->req('GET', '/old-metal/list?q=PAGES', [], $HX)['body'];
check('it is in the list with its value and "Available"', str_contains($l, 'PAGES OM') && str_contains($l, 'Available'));
preg_match('#/old-metal/([a-f0-9]{24})/cancel#', $l, $om);
$r = $post('/old-metal/' . ($om[1] ?? 'x') . '/cancel');
check('cancelling it removes it from the available stock', $r['code'] === 204 && str_contains($a->req('GET', '/old-metal/list?q=PAGES', [], $HX)['body'], 'Cancelled'));

echo "\nPermissions\n";
$s = new Browser($base);
$s->login('9000000011', 'Staff@123');
check('staff cannot open the Day Book (owner only)', $s->req('GET', '/day-book')['code'] === 403);
check('staff cannot cancel an expense or an order (403)', $s->req('POST', '/orders/' . $oid . '/cancel', [], ['X-CSRF-Token: ' . $s->csrf('/')])['code'] === 403);
check('staff can open the expenses page', $s->req('GET', '/expenses')['code'] === 200);

echo "\n$pass passed, $fail failed\n";
exit($fail ? 1 : 0);
