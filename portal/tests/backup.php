<?php
declare(strict_types=1);

/**
 * End-to-end test of Admin Control > Data backup against a RUNNING portal and dev API:
 *   php tests/backup.php [http://localhost:8080] [http://localhost:5000/api] [mongodb://127.0.0.1:27018/lgp_dev]
 * It only READS the dev database (the third argument) and downloads a zip of it. DEV database only. Never run against production.
 */
require __DIR__ . '/Browser.php';

$base = rtrim($argv[1] ?? 'http://localhost:8080', '/');
$devUri = $argv[3] ?? 'mongodb://127.0.0.1:27018/lgp_dev';
$pass = 0;
$fail = 0;
function check(string $name, bool $ok, string $detail = ''): void
{
    global $pass, $fail;
    if ($ok) { $pass++; echo "  ok    $name\n"; } else { $fail++; echo "  FAIL  $name $detail\n"; }
}
$HX = ['HX-Request: true'];

echo "Page\n";
$a = new Browser($base);
$a->login('7029621489', 'Admin@123');
$tok = $a->csrf('/');
$post = fn (string $path, array $form = [], array $hx = ['HX-Request: true']) => $a->req('POST', $path, $form, array_merge(['X-CSRF-Token: ' . $tok], $hx));
$r = $a->req('GET', '/admin/backup');
check('the page opens for the admin, with the address box and the check button', $r['code'] === 200 && str_contains($r['body'], 'Data backup') && str_contains($r['body'], 'name="uri"') && str_contains($r['body'], 'Check connection'));
check('the address box is a password-style field that is not pre-filled', !str_contains($r['body'], 'mongodb://127') && !preg_match('/name="uri"[^>]*value=/', $r['body']));
check('the menu shows Data backup to the admin', str_contains($r['body'], 'href="/admin/backup"'));

echo "\nStaff cannot\n";
$s = new Browser($base);
$s->login('9000000011', 'Staff@123');
$st = $s->csrf('/');
check('a staff login cannot open the page (403)', $s->req('GET', '/admin/backup')['code'] === 403);
check('and cannot post to it either', $s->req('POST', '/admin/backup/download', ['uri' => $devUri, 'db' => ['x']], ['X-CSRF-Token: ' . $st])['code'] === 403);
check('and the staff menu does not show it', !str_contains($s->req('GET', '/')['body'], 'href="/admin/backup"'));

echo "\nCheck the connection\n";
$r = $post('/admin/backup/inspect', ['uri' => '']);
check('an empty address is explained (422, shown in the block)', $r['code'] === 422 && str_contains($r['body'], 'notice-error') && str_contains($r['body'], 'Paste'));
$r = $post('/admin/backup/inspect', ['uri' => 'http://example.com']);
check('an address that is not a MongoDB one is explained', $r['code'] === 422 && str_contains($r['body'], 'must start with mongodb'));
$secret = 'Zx9Qv7LmPw44';
$r = $post('/admin/backup/inspect', ['uri' => "mongodb://someone:$secret@127.0.0.1:1/nothing"]);
check('an unreachable server is explained, and the password never comes back in the answer', $r['code'] === 422 && str_contains($r['body'], 'Could not reach') && !str_contains($r['body'], $secret), substr(strip_tags($r['body']), 0, 160));
$r = $post('/admin/backup/inspect', ['uri' => $devUri]);
check('the dev database is listed with its collections and counts', $r['code'] === 200 && str_contains($r['body'], 'name="db[]"') && str_contains($r['body'], 'lgp_dev') && str_contains($r['body'], 'items') && str_contains($r['body'], 'documents'), substr(strip_tags($r['body']), 0, 200));
check('the listing never repeats the address or its user', !str_contains($r['body'], $devUri) && !str_contains($r['body'], 'name="uri"'));
check('system databases are not offered', !preg_match('/value="(admin|local|config)"/', $r['body']));

echo "\nDownload\n";
$r = $a->req('POST', '/admin/backup/download', ['uri' => $devUri, 'db' => ['lgp_dev'], 'readable' => ''], ['X-CSRF-Token: ' . $tok]);
$h = $r['headers'];
check('the answer is a zip file download', $r['code'] === 200 && str_starts_with((string) ($h['content-type'] ?? ''), 'application/zip') && str_contains((string) ($h['content-disposition'] ?? ''), 'attachment') && str_contains((string) ($h['content-disposition'] ?? ''), '.zip'), json_encode($h));
check('it really is a zip (starts with PK) and is not empty', str_starts_with($r['body'], 'PK') && strlen($r['body']) > 2000, 'bytes: ' . strlen($r['body']));
check('it holds the manifest, the restore README and the data of the chosen database', str_contains($r['body'], 'manifest.json') && str_contains($r['body'], 'README-restore.txt') && str_contains($r['body'], 'dump/lgp_dev/items.bson'));
check('no readable copy when it was not ticked', !str_contains($r['body'], 'readable/'));
check('the browser is told not to cache it', str_contains((string) ($h['cache-control'] ?? ''), 'no-store'));
$r = $a->req('POST', '/admin/backup/download', ['uri' => $devUri, 'db' => ['lgp_dev'], 'readable' => '1'], ['X-CSRF-Token: ' . $tok]);
check('with the readable copy ticked the zip also has readable/ files', str_contains($r['body'], 'readable/lgp_dev/items.jsonl'));

echo "\nWhen it cannot download\n";
$r = $a->req('POST', '/admin/backup/download', ['uri' => $devUri], ['X-CSRF-Token: ' . $tok]);
check('nothing ticked sends the person back with a message (no file)', $r['code'] === 302 && !str_starts_with($r['body'], 'PK'));
$r = $a->req('POST', '/admin/backup/download', ['uri' => 'mongodb://nobody:' . $secret . '@127.0.0.1:1/x', 'db' => ['x']], ['X-CSRF-Token: ' . $tok]);
check('a failing connection sends the person back with a message (no broken file)', $r['code'] === 302 && !str_starts_with($r['body'], 'PK'));
$page = $a->req('GET', '/admin/backup')['body'];
check('the message is on the page and does not hold the password', str_contains($page, 'notice-error') && !str_contains($page, $secret));
$r = $a->req('POST', '/admin/backup/download', ['uri' => $devUri, 'db' => ['lgp_dev']]);
check('a post without the secret token is refused', in_array($r['code'], [403, 419], true), (string) $r['code']);

echo "\nAudit trail\n";
$au = $a->req('GET', '/admin/audit?entity=backup')['body'];
check('the downloads are in the audit log as Data backups, with counts but no address', str_contains($au, 'Data backups') && str_contains($au, 'Downloaded') && !str_contains($au, '127.0.0.1:27018/jewellery') && !str_contains($au, $secret));

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
