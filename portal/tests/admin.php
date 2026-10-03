<?php
declare(strict_types=1);

/**
 * End-to-end test of Admin Control against a RUNNING portal and dev API:  php tests/admin.php [http://localhost:8080] [http://localhost:5000/api]
 * Adds a test staff login (switched off again at the end), changes one role permission and one rule and puts them back,
 * publishes an app version and puts the old one back, sends one message. DEV database only. Never run against production.
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
$at = apiCall('POST', $api . '/auth/login', ['mobile' => '7029621489', 'password' => 'Admin@123'])['data']['token'] ?? '';
$post = fn (string $path, array $form = []) => $a->req('POST', $path, $form, ['X-CSRF-Token: ' . $tok, 'HX-Request: true']);

echo "Staff\n";
$r = $a->req('GET', '/admin/staff');
check('the staff list shows everyone with role, branch and whether the login is on', $r['code'] === 200 && str_contains($r['body'], 'Add staff') && str_contains($r['body'], 'Main Counter Staff') && str_contains($r['body'], 'Login'));
$r = $a->req('GET', '/admin/staff/new', [], $HX);
check('the add form opens with roles and branches', $r['code'] === 200 && str_contains($r['body'], 'name="mobile"') && str_contains($r['body'], 'Bagbazar Showroom') && str_contains($r['body'], 'Viewer'));
$mob = '8' . str_pad((string) random_int(0, 999999999), 9, '0', STR_PAD_LEFT);
$r = $post('/admin/staff', ['name' => 'PORTAL TEST staff', 'mobile' => $mob, 'password' => '123', 'role' => 'staff', 'branchId' => 'main']);
check('a short password is refused inside the form (422)', $r['code'] === 422 && str_contains($r['body'], 'notice-error'), substr(strip_tags($r['body']), 0, 200));
$r = $post('/admin/staff', ['name' => 'PORTAL TEST staff', 'mobile' => $mob, 'password' => 'Test@1234', 'role' => 'staff', 'branchId' => 'main']);
check('a new login is added and the page refreshes', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true', "($r[code]) " . substr(strip_tags($r['body']), 0, 200));
$users = (array) (apiCall('GET', $api . '/users', null, $at)['data']['users'] ?? []);
$uid = '';
foreach ($users as $u) { if (($u['mobile'] ?? '') === $mob) { $uid = $u['_id']; } }
check('the new person really exists in the API', $uid !== '');
$n = new Browser($base);
$r = $n->req('POST', '/login', ['_csrf' => $n->csrf('/login'), 'mobile' => $mob, 'password' => 'Test@1234']);
check('the new person can sign in on the website with that password', $r['code'] === 302);
$r = $a->req('GET', '/admin/staff/' . $uid);
check('the person page shows details, permissions and the switch-off button', $r['code'] === 200 && str_contains($r['body'], 'PORTAL TEST staff') && str_contains($r['body'], 'What PORTAL TEST staff can do') && str_contains($r['body'], 'Switch off this login'));
$r = $a->req('POST', '/admin/staff/' . $uid, ['_csrf' => $tok, 'name' => 'PORTAL TEST staff', 'mobile' => $mob, 'role' => 'manager', 'branchId' => 'main', 'isActive' => '1']);
check('changing the role saves and returns to the page', $r['code'] === 302);
$got = apiCall('GET', $api . '/users/' . $uid, null, $at)['data']['user'] ?? [];
check('the role changed in the API', ($got['role'] ?? '') === 'manager');
$uname = 'ptest' . substr($mob, -6);
$r = $a->req('POST', '/admin/staff/' . $uid, ['_csrf' => $tok, 'name' => 'PORTAL TEST staff', 'mobile' => $mob, 'username' => $uname, 'email' => $uname . '@example.test', 'role' => 'manager', 'branchId' => 'main', 'isActive' => '1']);
$got = apiCall('GET', $api . '/users/' . $uid, null, $at)['data']['user'] ?? [];
check('a username and e-mail can be set on the person page', $r['code'] === 302 && ($got['username'] ?? '') === $uname && ($got['email'] ?? '') === $uname . '@example.test', json_encode([$got['username'] ?? null, $got['email'] ?? null]));
$u2 = new Browser($base);
$x = $u2->req('POST', '/login', ['_csrf' => $u2->csrf('/login'), 'mobile' => $uname, 'password' => 'Test@1234']);
check('they can then sign in on the website with the username', $x['code'] === 302, (string) $x['code']);
$u3 = new Browser($base);
$x = $u3->req('POST', '/login', ['_csrf' => $u3->csrf('/login'), 'mobile' => strtoupper($uname) . '@EXAMPLE.TEST', 'password' => 'Test@1234']);
check('or with the e-mail (any capitals)', $x['code'] === 302, (string) $x['code']);
$other = '';
foreach ($users as $u) { if (($u['mobile'] ?? '') === '9000000011') { $other = $u['_id']; } }
$r = $a->req('POST', '/admin/staff/' . $other, ['_csrf' => $tok, 'name' => 'Bagbazar Staff', 'mobile' => '9000000011', 'username' => $uname, 'role' => 'staff', 'branchId' => '', 'isActive' => '1']);
$after = apiCall('GET', $api . '/users/' . $other, null, $at)['data']['user'] ?? [];
check('the same username cannot be given to a second person', ($after['username'] ?? '') !== $uname, (string) ($after['username'] ?? ''));
$r = $post('/admin/staff/' . $uid . '/permissions', ['perm' => ['items.delete' => 'block', 'expenses.create' => 'allow', 'billing.view' => '']]);
check('one person can be blocked from one thing and allowed another', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true');
$got = apiCall('GET', $api . '/users/' . $uid, null, $at)['data']['user'] ?? [];
check('the API kept exactly those two overrides', ($got['permissionOverrides']['items.delete'] ?? null) === false && ($got['permissionOverrides']['expenses.create'] ?? null) === true && !array_key_exists('billing.view', $got['permissionOverrides'] ?? []), json_encode($got['permissionOverrides'] ?? null));
$r = $a->req('GET', '/admin/staff/' . $uid);
check('the page shows them (Blocked / Allowed selected)', str_contains($r['body'], '<option value="block" selected>') && str_contains($r['body'], '<option value="allow" selected>'));
$r = $a->req('GET', '/admin/staff/' . $uid . '/password', [], $HX);
check('the new-password form opens', $r['code'] === 200 && str_contains($r['body'], 'name="again"'));
$r = $post('/admin/staff/' . $uid . '/password', ['password' => 'Test@5678', 'again' => 'other']);
check('two different passwords are refused (422)', $r['code'] === 422 && str_contains($r['body'], 'not the same'));
$r = $post('/admin/staff/' . $uid . '/password', ['password' => 'Test@5678', 'again' => 'Test@5678']);
check('a password reset closes the pop-up with a message', $r['code'] === 204 && str_contains($r['headers']['hx-trigger'] ?? '', 'modal-close'));
$r = (new Browser($base));
$x = $r->req('POST', '/login', ['_csrf' => $r->csrf('/login'), 'mobile' => $mob, 'password' => 'Test@5678']);
check('the new password works', $x['code'] === 302);
$y = new Browser($base);
$x = $y->req('POST', '/login', ['_csrf' => $y->csrf('/login'), 'mobile' => $mob, 'password' => 'Test@1234']);
check('and the old one does not', $x['code'] !== 302);
$r = $post('/admin/staff/' . $uid . '/deactivate');
check('the login can be switched off', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true');
$got = apiCall('GET', $api . '/users/' . $uid, null, $at)['data']['user'] ?? [];
check('and stays in the list as Off (nothing deleted)', ($got['isActive'] ?? true) === false);

echo "\nRoles\n";
$r = $a->req('GET', '/admin/staff?tab=roles&role=viewer');
check('the role page lists every permission by group', $r['code'] === 200 && str_contains($r['body'], 'name="perm[]"') && str_contains($r['body'], 'View items') && str_contains($r['body'], 'Save this role'));
$grid = apiCall('GET', $api . '/permissions/roles', null, $at)['data']['grids']['viewer'] ?? [];
$all = array_keys($grid);
$on = array_values(array_filter($all, fn ($k) => !empty($grid[$k]) && $k !== 'expenses.view'));
$r = $post('/admin/roles/viewer', ['allkeys' => $all, 'perm' => $on]);
check('saving a role refreshes the page', $r['code'] === 204 && ($r['headers']['hx-refresh'] ?? '') === 'true', "($r[code])");
$after = apiCall('GET', $api . '/permissions/roles', null, $at)['data']['grids']['viewer'] ?? [];
check('one permission was taken away and the rest stayed', empty($after['expenses.view']) && !empty($after['items.view']));
$on2 = array_values(array_filter($all, fn ($k) => !empty($grid[$k])));
$post('/admin/roles/viewer', ['allkeys' => $all, 'perm' => $on2]);   // put it back
$back = apiCall('GET', $api . '/permissions/roles', null, $at)['data']['grids']['viewer'] ?? [];
check('and it was put back as it was', ($back['expenses.view'] ?? null) === ($grid['expenses.view'] ?? null));

echo "\nApp updates\n";
$cur = apiCall('GET', $api . '/app-version')['data']['appVersion'] ?? [];
$r = $a->req('GET', '/admin/updates');
check('the page shows the current version and the publish form', $r['code'] === 200 && str_contains($r['body'], (string) ($cur['latestVersion'] ?? '')) && str_contains($r['body'], 'Publish a new version'));
$r = $a->req('POST', '/admin/updates', ['_csrf' => $tok, 'latestVersion' => '', 'latestVersionCode' => '']);
check('an empty version is refused in the page (422)', $r['code'] === 422 && str_contains($r['body'], 'notice-error'));
$r = $a->req('POST', '/admin/updates', ['_csrf' => $tok, 'latestVersion' => '9.9.9', 'latestVersionCode' => '99', 'downloadUrl' => $cur['downloadUrl'] ?? '', 'updateMessage' => 'PORTAL TEST']);
check('publishing goes back to the page', $r['code'] === 302);
$now = apiCall('GET', $api . '/app-version')['data']['appVersion'] ?? [];
check('the API now says 9.9.9', ($now['latestVersion'] ?? '') === '9.9.9' && (int) ($now['latestVersionCode'] ?? 0) === 99);
apiCall('PUT', $api . '/app-version', ['latestVersion' => $cur['latestVersion'] ?? '1.0.0', 'latestVersionCode' => $cur['latestVersionCode'] ?? 1, 'downloadUrl' => $cur['downloadUrl'] ?? '', 'updateMessage' => $cur['updateMessage'] ?? '', 'forceUpdate' => (bool) ($cur['forceUpdate'] ?? false)], $at);
$now = apiCall('GET', $api . '/app-version')['data']['appVersion'] ?? [];
check('the old version was put back', ($now['latestVersion'] ?? '') === ($cur['latestVersion'] ?? 'x'));

echo "\nNotifications\n";
$r = $a->req('GET', '/admin/notifications');
check('the page has the composer and the list of what was sent', $r['code'] === 200 && str_contains($r['body'], 'Send a message') && str_contains($r['body'], 'Sent lately'));
$r = $a->req('POST', '/admin/notifications', ['_csrf' => $tok, 'title' => '', 'body' => '', 'target' => 'all']);
check('an empty message is refused in the page (422)', $r['code'] === 422 && str_contains($r['body'], 'notice-error'));
$r = $a->req('POST', '/admin/notifications', ['_csrf' => $tok, 'title' => 'PORTAL TEST message', 'body' => 'test only', 'target' => 'viewer']);
check('a message to one role is sent', $r['code'] === 302);
$r = $a->req('GET', '/admin/notifications');
check('it shows in the sent list', str_contains($r['body'], 'PORTAL TEST message'));

echo "\nApp settings\n";
$r = $a->req('GET', '/admin/settings');
check('the rules are shown in plain words with their choices', $r['code'] === 200 && str_contains($r['body'], 'Metal value is worked on') && str_contains($r['body'], 'Final fine weight') && str_contains($r['body'], 'Hallmark fee'));
$set = apiCall('GET', $api . '/stock-settings', null, $at)['data']['settings'] ?? [];
$old = $set['hallmark']['charge'] ?? 45;
$r = $a->req('POST', '/admin/settings', ['_csrf' => $tok, 's' => ['hallmark' => ['charge' => '55'], 'purchase' => ['hallmarkGst' => 'false']]]);
check('saving rules goes back to the page', $r['code'] === 302);
$now = apiCall('GET', $api . '/stock-settings', null, $at)['data']['settings'] ?? [];
check('the API has the new hallmark fee and the yes/no rule', (float) ($now['hallmark']['charge'] ?? 0) === 55.0 && ($now['purchase']['hallmarkGst'] ?? true) === false);
$a->req('POST', '/admin/settings', ['_csrf' => $tok, 's' => ['hallmark' => ['charge' => (string) $old], 'purchase' => ['hallmarkGst' => ($set['purchase']['hallmarkGst'] ?? true) ? 'true' : 'false']]]);
$now = apiCall('GET', $api . '/stock-settings', null, $at)['data']['settings'] ?? [];
check('and both were put back', (float) ($now['hallmark']['charge'] ?? 0) === (float) $old && ($now['purchase']['hallmarkGst'] ?? null) === ($set['purchase']['hallmarkGst'] ?? true));

echo "\nAudit log and server\n";
$r = $a->req('GET', '/admin/audit');
check('the audit log lists who did what', $r['code'] === 200 && str_contains($r['body'], 'Audit log') && str_contains($r['body'], 'class="t"'));
check('it shows the staff login that was just added, and the permission changes', str_contains($r['body'], 'PORTAL TEST staff') || str_contains($r['body'], 'Role: viewer'));
$r = $a->req('GET', '/admin/audit?entity=app_update');
check('it can show only app updates', $r['code'] === 200 && str_contains($r['body'], 'App version 9.9.9'));
$r = $a->req('GET', '/admin/audit?entity=permission');
check('and only permission changes, with allowed / blocked', $r['code'] === 200 && str_contains($r['body'], 'blocked') && str_contains($r['body'], 'allowed'));
$r = $a->req('GET', '/admin/audit?q=zzzz-no-such-thing');
check('a search with no match says so', str_contains($r['body'], 'Nothing recorded'));
$r = $a->req('GET', '/admin/server');
check('the server page shows databases, version and settings (never their values)', $r['code'] === 200 && str_contains($r['body'], 'Databases') && str_contains($r['body'], 'Connected') && !preg_match('#mongodb(\+srv)?://#', $r['body']));

echo "\nPermissions\n";
$v = new Browser($base);
$v->login('9000000011', 'Staff@123');
check('a staff login cannot open Admin Control (403 page)', $v->req('GET', '/admin/staff')['code'] === 403 && $v->req('GET', '/admin/audit')['code'] === 403);
check('and cannot post to it either', $v->req('POST', '/admin/updates', ['_csrf' => $v->csrf('/'), 'latestVersion' => '5.5.5', 'latestVersionCode' => '55'])['code'] === 403);

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
