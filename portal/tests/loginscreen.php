<?php
declare(strict_types=1);

/**
 * The "Login screen" page (pictures of the app sign-in screen) against a RUNNING portal and dev API:
 *   php tests/loginscreen.php [http://localhost:8080] [http://localhost:5000/api]
 * The API must be started with a throw-away S3 (see backend/scripts/dev-fake-s3.js: S3_BUCKET + S3_ENDPOINT), otherwise the
 * pictures would go to Cloudinary. Leaves the app_login_slides collection as it found it (the test removes what it adds). DEV only.
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
function png(string $path, int $w, int $h, int $r, int $g, int $b): void
{
    $im = imagecreatetruecolor($w, $h);
    imagefill($im, 0, 0, imagecolorallocate($im, $r, $g, $b));
    imagepng($im, $path);
    imagedestroy($im);
}

$a = new Browser($base);
$a->login('7029621489', 'Admin@123');
$tok = $a->csrf('/');
$s = new Browser($base);
$s->login('9000000011', 'Staff@123');
$stok = $s->csrf('/');
$at = apiCall('POST', $api . '/auth/login', ['mobile' => '7029621489', 'password' => 'Admin@123'])['data']['token'] ?? '';
$list = fn () => (array) (apiCall('GET', $api . '/app-assets/login-slides/admin', null, $at)['data']['slides'] ?? []);
$existing = array_map(fn ($x) => $x['id'], $list());
$added = [];
$tmp = sys_get_temp_dir();

echo "Login screen page\n";
$r = $a->req('GET', '/admin/login-screen');
check('the page opens for an admin and shows the size guide (1080 x 1350, 4:5)', $r['code'] === 200 && str_contains($r['body'], '1080 × 1350') && str_contains($r['body'], 'Add a picture'), (string) $r['code']);
$r = $a->req('GET', '/');
check('it is in the Admin Control menu', str_contains($r['body'], '/admin/login-screen'));
check('a staff login cannot open it or change anything (403)', $s->req('GET', '/admin/login-screen')['code'] === 403
    && $s->upload('/admin/login-screen', ['_csrf' => $stok], 'image', __FILE__, 'x.png')['code'] === 403);

$r = $a->req('POST', '/admin/login-screen', ['_csrf' => $tok]);
check('no file chosen is explained (422)', $r['code'] === 422 && str_contains($r['body'], 'Choose a picture'), (string) $r['code']);
$r = $a->upload('/admin/login-screen', ['_csrf' => $tok], 'image', __FILE__, 'script.png');
check('a file that is not a picture is refused with the server\'s words (422)', $r['code'] === 422 && str_contains($r['body'], 'notice-error'), (string) $r['code']);

$f1 = $tmp . '/lgp-slide-1.png';
png($f1, 1080, 1350, 200, 60, 80);
$r = $a->upload('/admin/login-screen', ['_csrf' => $tok, 'captionEn' => 'PORTAL TEST ONE', 'captionBn' => 'পরীক্ষা এক'], 'image', $f1, 'one.png');
check('adding a picture redirects back to the page', $r['code'] === 302 && str_contains($r['headers']['location'] ?? '', '/admin/login-screen'), (string) $r['code'] . ' ' . substr(strip_tags($r['body']), 0, 200));
$now = $list();
$mine = array_values(array_filter($now, fn ($x) => !in_array($x['id'], $existing, true)));
check('the API now holds it with its captions', count($mine) === 1 && $mine[0]['captionEn'] === 'PORTAL TEST ONE' && $mine[0]['captionBn'] === 'পরীক্ষা এক' && $mine[0]['active'] === true, json_encode($mine));
$added = array_map(fn ($x) => $x['id'], $mine);
$id1 = $mine[0]['id'] ?? '';
$r = $a->req('GET', '/admin/login-screen');
check('the page lists it with its picture and captions', str_contains($r['body'], 'PORTAL TEST ONE') && str_contains($r['body'], $mine[0]['imageUrl'] ?? '#'));
check('the picture is public to the app (no sign-in)', in_array($id1, array_map(fn ($x) => $x['id'], (array) (apiCall('GET', $api . '/app-assets/login-slides')['data']['slides'] ?? [])), true));

$f2 = $tmp . '/lgp-slide-2.png';
png($f2, 1080, 1350, 40, 90, 200);
$a->upload('/admin/login-screen', ['_csrf' => $tok, 'captionEn' => 'PORTAL TEST TWO'], 'image', $f2, 'two.png');
$now = $list();
$id2 = '';
foreach ($now as $x) { if ($x['captionEn'] === 'PORTAL TEST TWO') { $id2 = $x['id']; $added[] = $id2; } }
check('a second picture is added after the first', $id2 !== '' && array_search($id2, array_column($now, 'id'), true) > array_search($id1, array_column($now, 'id'), true));

$r = $a->req('POST', "/admin/login-screen/$id2/move", ['_csrf' => $tok, 'dir' => 'up']);
$now = $list();
check('"Earlier" moves it one place up', $r['code'] === 302 && array_search($id2, array_column($now, 'id'), true) < array_search($id1, array_column($now, 'id'), true));
$a->req('POST', "/admin/login-screen/$id2/move", ['_csrf' => $tok, 'dir' => 'down']);
$now = $list();
check('"Later" puts it back', array_search($id2, array_column($now, 'id'), true) > array_search($id1, array_column($now, 'id'), true));

$r = $a->req('POST', "/admin/login-screen/$id1", ['_csrf' => $tok, 'captionEn' => 'PORTAL TEST ONE EDITED', 'captionBn' => '']);
$one = array_values(array_filter($list(), fn ($x) => $x['id'] === $id1))[0] ?? [];
check('saving changes the words and, with the box unticked, hides it from the app', $r['code'] === 302 && ($one['captionEn'] ?? '') === 'PORTAL TEST ONE EDITED' && ($one['active'] ?? true) === false
    && !in_array($id1, array_map(fn ($x) => $x['id'], (array) (apiCall('GET', $api . '/app-assets/login-slides')['data']['slides'] ?? [])), true));
$a->req('POST', "/admin/login-screen/$id1", ['_csrf' => $tok, 'captionEn' => 'PORTAL TEST ONE', 'active' => '1']);
$one = array_values(array_filter($list(), fn ($x) => $x['id'] === $id1))[0] ?? [];
check('ticking it again shows it again', ($one['active'] ?? false) === true);

foreach ([$id1, $id2] as $id) {
    $r = $a->req('POST', "/admin/login-screen/$id/delete", ['_csrf' => $tok]);
    check("removing $id works", $r['code'] === 302);
}
check('both are gone from the API', count(array_filter($list(), fn ($x) => in_array($x['id'], $added, true))) === 0);
@unlink($f1);
@unlink($f2);
// belt and braces: remove anything this run added that is still there
foreach ($added as $id) { apiCall('DELETE', $api . '/app-assets/login-slides/' . $id, null, $at); }

echo "\n$pass passed, $fail failed\n";
exit($fail ? 1 : 0);
