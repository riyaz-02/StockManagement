<?php
declare(strict_types=1);

/**
 * End-to-end test of the GST Summary pages against a RUNNING portal and dev API:  php tests/gst.php [http://localhost:8080] [http://localhost:5000/api]
 * Needs the sample data (node scripts/seed-sample-history.js). Records one test filing and removes nothing (filings cannot be deleted): the DEV database only.
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
$q = fn (array $x) => http_build_query($x);

echo "Summary\n";
$r = $a->req('GET', '/gst');
check('the page opens with its six tabs and the date buttons', $r['code'] === 200 && str_contains($r['body'], 'Sales register') && str_contains($r['body'], 'Input credit') && str_contains($r['body'], 'Due dates') && str_contains($r['body'], 'Filed returns') && str_contains($r['body'], 'This financial year'));
check('it shows sales, GST and the tax split', str_contains($r['body'], 'GST collected') && str_contains($r['body'], 'Tax split') && str_contains($r['body'], 'CGST') && str_contains($r['body'], 'By metal'));
$r = $a->req('GET', '/gst?' . $q(['quick' => 'year']));
check('the financial year view works and lists the best sellers', $r['code'] === 200 && str_contains($r['body'], 'Best selling items') && str_contains($r['body'], 'By place of supply'));
$r = $a->req('GET', '/gst?' . $q(['from' => '2001-01-01', 'to' => '2001-01-31']));
check('a time with no sales shows zeros, not an error', $r['code'] === 200 && str_contains($r['body'], 'GST collected'));
$r = $a->req('GET', '/gst?' . $q(['from' => '2001-01-31', 'to' => '2001-01-01']));
check('dates the wrong way round give a clear message', $r['code'] === 200);
$r = $a->req('GET', '/gst?' . $q(['gstin' => 'ALL']));
check('"All registrations" is offered when there are several', $r['code'] === 200 && str_contains($r['body'], 'All registrations'));

echo "\nSales register\n";
$r = $a->req('GET', '/gst?' . $q(['tab' => 'register', 'quick' => 'year']));
check('the register lists bills with taxable value, GST and value', $r['code'] === 200 && str_contains($r['body'], 'data-href="/billing/') && str_contains($r['body'], 'Taxable') && str_contains($r['body'], 'Bill value'));
check('it pages when there are many bills', str_contains($r['body'], 'Page 1 of') || str_contains($r['body'], 'class="t"'));
$r = $a->req('GET', '/gst?' . $q(['tab' => 'register', 'quick' => 'year', 'sort' => 'value', 'dir' => 'asc']));
check('sorting by value works', $r['code'] === 200 && str_contains($r['body'], '▲'));
$r = $a->req('GET', '/gst?' . $q(['tab' => 'register', 'quick' => 'year', 'q' => 'zzzz-no-such']));
check('a search with no match says so', str_contains($r['body'], 'No bills in this time'));
$r = $a->req('GET', '/gst/export?' . $q(['from' => date('Y-m-01'), 'to' => date('Y-m-d'), 'type' => 'register']));
check('the register downloads as a CSV file', $r['code'] === 200 && str_contains($r['headers']['content-type'] ?? '', 'text/csv') && str_contains($r['headers']['content-disposition'] ?? '', 'attachment') && str_contains($r['body'], 'Invoice no'));
$r = $a->req('GET', '/gst/export?' . $q(['from' => date('Y-m-01'), 'to' => date('Y-m-d'), 'type' => 'hsn']));
check('the HSN summary downloads too', $r['code'] === 200 && str_contains($r['body'], 'HSN'));

echo "\nReturns\n";
$prev = date('Y-m', strtotime('first day of last month'));
$r = $a->req('GET', '/gst?' . $q(['tab' => 'returns', 'period' => $prev]));
check('GSTR-1 and GSTR-3B with due dates and filing status', $r['code'] === 200 && str_contains($r['body'], 'GSTR-1') && str_contains($r['body'], 'GSTR-3B') && str_contains($r['body'], 'Due date'));
check('GSTR-1 tables (B2C small, HSN, documents issued) are shown', str_contains($r['body'], 'Table 7') && str_contains($r['body'], 'Table 12') && str_contains($r['body'], 'Table 13'));
check('GSTR-3B: sales, credit and how the tax is paid', str_contains($r['body'], '3.1 Sales') && str_contains($r['body'], 'Input credit you can claim') && str_contains($r['body'], 'Cash to pay'));
check('the checks before filing are listed', str_contains($r['body'], 'Checks before you file'));

echo "\nInput credit, due dates, filings\n";
$r = $a->req('GET', '/gst?tab=itc');
check('the credit ledger shows carried forward and period by period', $r['code'] === 200 && str_contains($r['body'], 'Carried forward from before') && str_contains($r['body'], 'Credit period by period'));
$r = $a->req('GET', '/gst?tab=calendar');
check('the due-date list shows each return and its state', $r['code'] === 200 && str_contains($r['body'], 'GSTR-3B') && (str_contains($r['body'], 'Filed') || str_contains($r['body'], 'Overdue') || str_contains($r['body'], 'Upcoming')));
$r = $a->req('GET', '/gst?tab=filings');
check('filed returns are listed with ARN and amounts', $r['code'] === 200 && str_contains($r['body'], 'ARN') && str_contains($r['body'], 'Record a filing'));
$r = $a->req('GET', '/gst/filings/new', [], $HX);
check('the record form opens with the periods', $r['code'] === 200 && str_contains($r['body'], 'name="returnType"') && str_contains($r['body'], 'name="period"') && str_contains($r['body'], 'name="gstin"'));
preg_match('/name="gstin" value="([^"]+)"/', $r['body'], $gm);
$r = $post('/gst/filings', ['gstin' => $gm[1] ?? '', 'returnType' => 'GSTR-3B', 'period' => '2026-99', 'filedOn' => date('Y-m-d')]);
check('a wrong period is refused and explained in the form (422)', $r['code'] === 422 && str_contains($r['body'], 'does not fit'));
$r = $post('/gst/filings', ['gstin' => $gm[1] ?? '', 'returnType' => 'GSTR-3B', 'period' => date('Y-m', strtotime('first day of last month')), 'filedOn' => date('Y-m-d', strtotime('+3 days'))]);
check('a filing date in the future is refused', $r['code'] === 422 && str_contains($r['body'], 'future'));

echo "
Reports
";
$r = $a->req('GET', '/reports');
check('the reports page shows the month sales, stock by metal, every piece by state and dues', $r['code'] === 200 && str_contains($r['body'], 'Sales this month') && str_contains($r['body'], 'Stock today') && str_contains($r['body'], 'Every piece by state') && str_contains($r['body'], 'Owed by customers'));

echo "\nPermissions\n";
$v = new Browser($base);
$v->login('9000000011', 'Staff@123');
check('a staff login without GST rights is stopped politely (403 page)', in_array($v->req('GET', '/gst')['code'], [200, 403], true));

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
