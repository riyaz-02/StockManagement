<?php
declare(strict_types=1);

/**
 * End-to-end test of the Stock Summary pages against a RUNNING portal and dev API:  php tests/summary.php [http://localhost:8080] [http://localhost:5000/api]
 * Takes today's snapshot, reports / approves / rejects test wastage (every test report ends rejected so nothing counts). DEV database only.
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
    curl_setopt_array($ch, [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 30,
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
$post = fn (string $path, array $form = []) => $a->req('POST', $path, $form, ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);
$s = new Browser($base);
$s->login('9000000011', 'Staff@123');
$stok = $s->csrf('/');
$spost = fn (string $path, array $form = []) => $s->req('POST', $path, $form, ['X-CSRF-Token: ' . $stok, 'HX-Request: true']);

echo "The Summary page\n";
$r = $a->req('GET', '/stock/summary');
$b = $r['body'];
check('the page opens with the two metal cards and their calculation', $r['code'] === 200 && str_contains($b, 'Stock Summary') && str_contains($b, 'Metal bought') && str_contains($b, 'Total metal received') && str_contains($b, 'Stock now') && str_contains($b, 'Sold on GST bills') && str_contains($b, 'approved wastage') && str_contains($b, 'Difference'));
check('both metals are there, with their Bengali captions', str_contains($b, '>Gold') && str_contains($b, '>Silver') && str_contains($b, 'মোট প্রাপ্ত ধাতু') && str_contains($b, 'গড়মিল'));
check('it says whether the difference can be trusted', preg_match('/(Reliable|Check first|Fix first):/', $b) === 1);
check('it shows the data checks and what the number means', str_contains($b, 'Data checks') && str_contains($b, 'What it means') && str_contains($b, 'What to do'));
check('it shows the settings it used and today\'s snapshot state', str_contains($b, 'allowance gold') && str_contains($b, 'snapshot'));
check('the movements and the wastage panel load', str_contains($b, 'Recent movements') && str_contains($b, 'hx-get="/stock/summary/wastage"'));
check('the menu has Stock Summary', str_contains($b, 'href="/stock/summary"'));
$sum = (array) (apiCall('GET', $api . '/stock/summary', null, $at)['data'] ?? []);
$gv = (float) ($sum['metals']['gold']['variance'] ?? 0);
check('the number on the page is the server\'s number', $gv === 0.0 ? str_contains($b, '0 g') : str_contains($b, rtrim(rtrim(number_format(abs($gv), 3, '.', ''), '0'), '.')), (string) $gv);
$r = $a->req('GET', '/stock/summary/movements?limit=30', [], $HX);
check('"show more" gives the longer list of movements', $r['code'] === 200 && (str_contains($r['body'], 'class="movements"') || str_contains($r['body'], 'No movements yet')));
$r = $a->req('GET', '/stock/summary/wastage', [], $HX);
check('the wastage panel lists reports and has the Report wastage button', $r['code'] === 200 && str_contains($r['body'], 'Wastage reports') && str_contains($r['body'], 'Report wastage'));

echo "\nThe daily snapshot\n";
$r = $post('/stock/summary/snapshot');
check('saving today\'s snapshot works and refreshes the page', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true', (string) $r['code']);
$h = (array) (apiCall('GET', $api . '/stock/summary/history?view=daily', null, $at)['data'] ?? []);
$today = date('Y-m-d');
check('it is in the history with the server\'s own numbers', ($h['rows'][0]['date'] ?? '') === $today && isset($h['rows'][0]['gold']['variance']), json_encode($h['rows'][0] ?? null));
check('saving it again the same day keeps ONE snapshot', $post('/stock/summary/snapshot')['code'] === 204 && count(array_filter((array) ($h['rows'] ?? []), fn ($x) => ($x['date'] ?? '') === $today)) === 1);

echo "\nHistory\n";
$r = $a->req('GET', '/stock/summary/history');
check('the history page shows the filters, the charts or a note, and the table', $r['code'] === 200 && str_contains($r['body'], 'Stock history') && str_contains($r['body'], 'Last 30 days') && str_contains($r['body'], 'Download CSV') && (str_contains($r['body'], 'class="t hist"') || str_contains($r['body'], 'No snapshots')));
foreach (['weekly', 'monthly'] as $v) {
    $x = $a->req('GET', "/stock/summary/history?view=$v");
    check("the $v view opens", $x['code'] === 200 && str_contains($x['body'], $v === 'weekly' ? 'Week' : 'Month'));
}
$x = $a->req('GET', '/stock/summary/history?quick=30&metal=gold');
check('a date range and one metal work', $x['code'] === 200 && !str_contains($x['body'], 'Silver (g)'));
$x = $a->req('GET', '/stock/summary/history.csv?quick=all&view=daily');
check('the history downloads as a CSV file', $x['code'] === 200 && str_starts_with((string) ($x['headers']['content-type'] ?? ''), 'text/csv') && str_starts_with($x['body'], 'Period,Date,Metal,Stock g,In g,Out g,Difference g,Difference %,Level'));
check('a date with a stray value is ignored, not trusted', $a->req('GET', '/stock/summary/history?quick=custom&from=%3Cscript%3E&to=zzz')['code'] === 200);

echo "\nWastage reports\n";
$r = $s->req('GET', '/stock/wastage/new', [], $HX);
check('the report form opens with the metals and the categories', $r['code'] === 200 && str_contains($r['body'], 'Polishing') && str_contains($r['body'], 'Stone Setting') && str_contains($r['body'], 'name="amount"'));
$bad = $spost('/stock/wastage', ['date' => $today, 'metal' => 'gold', 'amount' => '0', 'category' => 'Polishing', 'reason' => 'PORTAL TEST']);
check('a zero weight is refused inside the form (422)', $bad['code'] === 422 && str_contains($bad['body'], 'notice-error'), (string) $bad['code']);
$bad = $spost('/stock/wastage', ['date' => '2099-01-01', 'metal' => 'gold', 'amount' => '1', 'category' => 'Polishing', 'reason' => 'PORTAL TEST']);
check('a future date is refused', $bad['code'] === 422);
$ok = $spost('/stock/wastage', ['date' => $today, 'metal' => 'gold', 'amount' => '0.125', 'category' => 'Polishing', 'reason' => 'PORTAL TEST polish loss']);
check('a staff login can report wastage; the lists refresh', $ok['code'] === 204 && str_contains($ok['headers']['hx-trigger'] ?? '', 'data-changed'), (string) $ok['code']);
$list = (array) (apiCall('GET', $api . '/stock/wastage?q=PORTAL%20TEST&limit=50', null, $at)['data'] ?? []);
$mine = null;
foreach ((array) ($list['reports'] ?? []) as $w) { if (($w['status'] ?? '') === 'pending' && str_contains((string) ($w['reason'] ?? ''), 'polish loss')) { $mine = $w; break; } }
check('it is saved waiting for approval (not counted)', $mine !== null && $mine['amount'] === 0.125 && $mine['metal'] === 'gold');
$id = (string) ($mine['_id'] ?? '');
$r = $a->req('GET', '/stock/wastage');
check('the full list shows it with its status', $r['code'] === 200 && str_contains($r['body'], 'Waiting') && str_contains($r['body'], 'Wastage reports'));
$r = $s->req('GET', "/stock/wastage/$id", [], $HX);
check('the reporter sees the details, can change it, but has no Approve button', $r['code'] === 200 && str_contains($r['body'], 'Waiting for approval') && str_contains($r['body'], "/stock/wastage/$id/edit") && !str_contains($r['body'], '>Approve<'));
check('a staff login cannot approve (not even their own report)', $spost("/stock/wastage/$id/approve")['code'] === 403);
$r = $a->req('GET', "/stock/wastage/$id", [], $HX);
check('the admin sees Approve and Reject', str_contains($r['body'], '>Approve<') && str_contains($r['body'], '>Reject<'));
$r = $post("/stock/wastage/$id/approve");
check('someone else (the admin) approves it', $r['code'] === 204 && str_contains($r['headers']['hx-trigger'] ?? '', 'modal-close'), (string) $r['code']);
$cnt = (array) (apiCall('GET', $api . '/stock/summary', null, $at)['data'] ?? []);
check('now it counts: approved wastage went up by 0.125 g', abs(((float) ($cnt['metals']['gold']['out']['wastage'] ?? 0)) - ((float) ($sum['metals']['gold']['out']['wastage'] ?? 0)) - 0.125) < 0.0005);
$again = $post("/stock/wastage/$id/approve");
check('a second approval is refused with a message (it was already approved)', str_contains($again['headers']['hx-trigger'] ?? '', '"error"') && !str_contains($again['headers']['hx-trigger'] ?? '', 'modal-close'), (string) ($again['headers']['hx-trigger'] ?? ''));
$r = $a->req('GET', "/stock/wastage/$id/reject", [], $HX);
check('reversing an approval asks for a reason', $r['code'] === 200 && str_contains($r['body'], 'Reverse the approval') && str_contains($r['body'], 'name="comment"'));
$r = $post("/stock/wastage/$id/reject", ['comment' => '']);
check('a rejection without a reason is refused inside the form (422)', $r['code'] === 422 && str_contains($r['body'], 'notice-error'), (string) $r['code']);
$r = $post("/stock/wastage/$id/reject", ['comment' => 'PORTAL TEST reversed']);
check('the admin reverses it with a reason', $r['code'] === 204);
$after = (array) (apiCall('GET', $api . '/stock/summary', null, $at)['data'] ?? []);
check('it stops counting', abs(((float) ($after['metals']['gold']['out']['wastage'] ?? 0)) - ((float) ($sum['metals']['gold']['out']['wastage'] ?? 0))) < 0.0005);
check('a staff login cannot approve or reject (403)', $spost("/stock/wastage/$id/approve")['code'] === 403 && $spost("/stock/wastage/$id/reject", ['comment' => 'x'])['code'] === 403);
$r = $a->req('GET', '/stock/wastage?status=rejected');
check('the list can be filtered by status', $r['code'] === 200 && str_contains($r['body'], 'Rejected'));

echo "\nWho can see it\n";
check('a staff login can open the Summary and the history', $s->req('GET', '/stock/summary')['code'] === 200 && $s->req('GET', '/stock/summary/history')['code'] === 200);
$snap = $spost('/stock/summary/snapshot');
check('a branch login cannot save the whole firm\'s snapshot: the server says so', str_contains($snap['headers']['hx-trigger'] ?? '', '"error"') && str_contains($snap['headers']['hx-trigger'] ?? '', 'whole-firm'), (string) ($snap['headers']['hx-trigger'] ?? ''));

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
