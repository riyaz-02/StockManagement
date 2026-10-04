<?php
declare(strict_types=1);

// Unit tests for the portal helpers (no server needed):  php tests/run.php
require __DIR__ . '/../vendor/autoload.php';

use Portal\Api\ApiException;
use Portal\Auth\Throttle;
use Portal\Config;
use Portal\Http\Controllers\WakeController;
use Portal\Support\I18n;
use Portal\Support\Money;

Config::load(dirname(__DIR__));
$pass = 0;
$fail = 0;
function check(string $name, bool $ok, string $detail = ''): void
{
    global $pass, $fail;
    if ($ok) { $pass++; echo "  ok    $name\n"; } else { $fail++; echo "  FAIL  $name $detail\n"; }
}

echo "Money (Indian format)\n";
check('1,23,456.00', Money::inr(123456) === "\u{20B9}1,23,456.00", Money::inr(123456));
check('small amounts keep no comma', Money::inr(999.5) === "\u{20B9}999.50");
check('lakhs and crores group by 2', Money::inr(12345678.9) === "\u{20B9}1,23,45,678.90", Money::inr(12345678.9));
check('negative', Money::inr(-2060) === "-\u{20B9}2,060.00");
check('zero decimals', Money::inr(14000, 0) === "\u{20B9}14,000");
check('null and text are zero', Money::inr(null) === "\u{20B9}0.00" && Money::inr('abc') === "\u{20B9}0.00");
check('no symbol', Money::inr(1500, 2, false) === '1,500.00');
check('grams trims zeros', Money::grams(2.5) === '2.5 g' && Money::grams(4) === '4 g' && Money::grams(0.125) === '0.125 g');

echo "\nAfter-login redirect is same-site only\n";
check('a normal path passes', WakeController::safeNext('/billing?x=1') === '/billing?x=1');
check('a full URL is refused', WakeController::safeNext('https://evil.com') === '/');
check('protocol-relative is refused', WakeController::safeNext('//evil.com') === '/');
check('backslash trick is refused', WakeController::safeNext('/\\evil.com') === '/');
check('empty / null go home', WakeController::safeNext('') === '/' && WakeController::safeNext(null) === '/');

echo "\nWords (English first, missing keys fall back)\n";
I18n::load('en');
check('a known key', I18n::t('login.button') === 'Login');
check('variables are filled', I18n::t('login.wait', ['min' => 5]) === 'Too many wrong tries. Please wait 5 minute(s) and try again.');
check('an unknown key shows the key, never an error', I18n::t('no.such.key') === 'no.such.key');
I18n::load('xx');
check('a language with no file falls back to English', I18n::t('login.button') === 'Login');
I18n::load('en');
$enKeys = array_keys(require dirname(__DIR__) . '/lang/en.php');
check('every menu item has a name in the words file', (function () use ($enKeys) {
    foreach (Portal\Support\Nav::forAll() as $it) {
        if (!in_array('nav.' . $it['key'], $enKeys, true)) { echo "        missing nav." . $it['key'] . "\n"; return false; }
    }
    return true;
})());

echo "\nLogin brake (per person)\n";
$key = 'test|' . bin2hex(random_bytes(4));
check('a fresh person may try', Throttle::wait($key) === 0);
for ($i = 0; $i < 6; $i++) { Throttle::fail($key); }
check('after 6 wrong tries they must wait', Throttle::wait($key) > 0);
check('someone else is not blocked', Throttle::wait('other|' . bin2hex(random_bytes(4))) === 0);
Throttle::clear($key);
check('a good login clears the brake', Throttle::wait($key) === 0);

echo "\nAPI errors are classified\n";
check('no answer = down', (new ApiException('x', 0))->down());
check('502 / 503 / 504 = down', (new ApiException('x', 502))->down() && (new ApiException('x', 503))->down() && (new ApiException('x', 504))->down());
check('401 = unauthorized, not down', (new ApiException('x', 401))->unauthorized() && !(new ApiException('x', 401))->down());
check('403 = forbidden', (new ApiException('x', 403))->forbidden());
check('400 is a plain error', !(new ApiException('x', 400))->down() && !(new ApiException('x', 400))->unauthorized());

echo "\nSettings\n";
putenv('PORTAL_TEST_X=fromenv');
check('a real environment variable wins over the file', Config::get('PORTAL_TEST_X', 'd') === 'fromenv');
putenv('PORTAL_TEST_X');
check('a missing value gives the default', Config::get('PORTAL_TEST_X', 'd') === 'd');

echo "\n$pass passed, $fail failed\n";
exit($fail ? 1 : 0);
