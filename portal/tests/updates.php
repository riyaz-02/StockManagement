<?php
declare(strict_types=1);

/**
 * The bell and the app-update page against a RUNNING portal and dev API:  php tests/updates.php [http://localhost:8080] [http://localhost:5000/api]
 * Needs the portal started with the raised PHP upload limits (dev-portal.ps1 does it) and, for the upload part, a built APK
 * (flutter_app/build/app/outputs/flutter-apk/app-release.apk). The uploaded file is only STAGED and then discarded; nothing is
 * published, so no phone is told anything. Puts the version settings back. DEV database only.
 */
require __DIR__ . '/Browser.php';

$base = rtrim($argv[1] ?? 'http://localhost:8080', '/');
$api = rtrim($argv[2] ?? 'http://localhost:5000/api', '/');
$apk = __DIR__ . '/../../flutter_app/build/app/outputs/flutter-apk/app-release.apk';
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
$st = apiCall('POST', $api . '/auth/login', ['mobile' => '9000000011', 'password' => 'Staff@123'])['data']['token'] ?? '';
$s = new Browser($base);
$s->login('9000000011', 'Staff@123');
$stok = $s->csrf('/');

echo "The bell\n";
$r = $a->req('GET', '/');
check('every page has the bell in the top bar', $r['code'] === 200 && str_contains($r['body'], 'class="bell"') && str_contains($r['body'], '/partials/bell/count') && str_contains($r['body'], '/partials/bell/list'));
apiCall('POST', $api . '/notifications/send', ['title' => 'PORTAL BELL TEST', 'body' => 'a test message', 'targetType' => 'all'], $at);
$r = $s->req('GET', '/partials/bell/count', [], $HX);
check('a staff login sees a number on the bell for the new message', $r['code'] === 200 && str_contains($r['body'], 'bell-badge'), substr($r['body'], 0, 120));
$r = $s->req('GET', '/partials/bell/list', [], $HX);
check('the list shows the message, marked new', $r['code'] === 200 && str_contains($r['body'], 'PORTAL BELL TEST') && str_contains($r['body'], 'is-unread') && str_contains($r['body'], 'Notifications'), substr(strip_tags($r['body']), 0, 200));
check('the list says when (relative time)', str_contains($r['body'], 'just now') || str_contains($r['body'], 'min ago'));
$r = $s->req('POST', '/partials/bell/seen', [], ['X-CSRF-Token: ' . $stok, 'HX-Request: true']);
check('opening the list marks it read and asks the bell to refresh', $r['code'] === 204 && str_contains($r['headers']['hx-trigger'] ?? '', 'bell-refresh'), (string) $r['code']);
$r = $s->req('GET', '/partials/bell/list', [], $HX);
check('after that the message is no longer marked new', str_contains($r['body'], 'PORTAL BELL TEST') && !str_contains($r['body'], 'is-unread'));
$r = $s->req('GET', '/partials/bell/count', [], $HX);
$feed = apiCall('GET', $api . '/notifications/feed', null, $st);
$rem = (int) ($feed['data']['reminders'] ?? 0);
check('the number on the bell is now only the reminders that are still open', (int) ($feed['data']['unread'] ?? -1) === $rem && (str_contains($r['body'], 'bell-badge') === ($rem > 0)));
$anon = (new Browser($base))->req('GET', '/partials/bell/count', [], $HX);
check('the bell needs a sign-in (an anonymous visitor is sent to /login, nothing is shown)', ($anon['headers']['hx-redirect'] ?? '') === '/login' && !str_contains($anon['body'], 'bell-badge'));

echo "\nApp updates page\n";
$r = $a->req('GET', '/admin/updates');
check('the page shows what is on the phones, the upload step and the releases', $r['code'] === 200 && str_contains($r['body'], 'On the phones now') && str_contains($r['body'], 'Upload the new app') && str_contains($r['body'], 'Releases') && str_contains($r['body'], 'enctype="multipart/form-data"'));
check('a staff login cannot open it or upload (403)', $s->req('GET', '/admin/updates')['code'] === 403 && $s->upload('/admin/updates/upload', ['_csrf' => $stok], 'apk', __FILE__, 'x.apk')['code'] === 403);
$r = $a->req('POST', '/admin/updates/upload', ['_csrf' => $tok]);
check('no file chosen is explained (422)', $r['code'] === 422 && str_contains($r['body'], 'Choose the APK'), (string) $r['code']);
$r = $a->upload('/admin/updates/upload', ['_csrf' => $tok], 'apk', __FILE__, 'notes.txt');
check('a file that is not an .apk is refused in words (422)', $r['code'] === 422 && str_contains($r['body'], 'not an .apk'));
$r = $a->upload('/admin/updates/upload', ['_csrf' => $tok], 'apk', __FILE__, 'fake.apk');
check('a fake .apk is refused by the server with its reason (422)', $r['code'] === 422 && str_contains($r['body'], 'not an APK'), substr(strip_tags($r['body']), 0, 300));

if (!is_file($apk)) {
    echo "  (no built APK: the upload step is skipped)\n";
} else {
    $cur = apiCall('GET', $api . '/app-version/admin', null, $at)['data']['appVersion'] ?? [];
    $oldCode = (int) ($cur['latestVersionCode'] ?? 1);
    $put = fn (int $code) => apiCall('PUT', $api . '/app-version', ['latestVersion' => (string) ($cur['latestVersion'] ?? '1.0.0'), 'latestVersionCode' => $code, 'forceUpdate' => (bool) ($cur['forceUpdate'] ?? false), 'downloadUrl' => (string) ($cur['downloadUrl'] ?? ''), 'updateMessage' => (string) ($cur['updateMessage'] ?? '')], $at);
    // what build number is inside the file? (asked of the same reader the server uses)
    $code = (int) trim((string) shell_exec('node -e "require(process.argv[1]).readApk(require(\'fs\').readFileSync(process.argv[2])).then(r=>console.log(r.versionCode))" ' . escapeshellarg(realpath(__DIR__ . '/../../backend/services/apkInfo.js')) . ' ' . escapeshellarg($apk)));
    $put($code - 1);   // phones are "one build behind", so this file counts as the newer one; put back at the end
    $r = $a->upload('/admin/updates/upload', ['_csrf' => $tok], 'apk', $apk, 'app-release.apk');
    check('the APK uploads and the page goes on to the review step', $r['code'] === 302 && ($r['headers']['location'] ?? '') === '/admin/updates', (string) $r['code'] . ' ' . substr(strip_tags($r['body']), 0, 300));
    $r = $a->req('GET', '/admin/updates');
    check('the review shows the version, the size and a Publish button', str_contains($r['body'], '2. Review and publish') && str_contains($r['body'], 'Publish ') && str_contains($r['body'], 'MB'));
    $pubNow = apiCall('GET', $api . '/app-version')['data']['appVersion'] ?? [];
    check('staging changed nothing for the phones', (int) ($pubNow['latestVersionCode'] ?? 0) === $code - 1 && !isset($pubNow['staged']));
    $r = $a->req('POST', '/admin/updates/discard', ['_csrf' => $tok]);
    check('discard removes it and the upload step is back', $r['code'] === 302 && str_contains($a->req('GET', '/admin/updates')['body'], '1. Upload the new app'));
    $put($oldCode);
}

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
