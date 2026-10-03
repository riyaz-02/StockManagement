<?php
declare(strict_types=1);

namespace Portal\Auth;

use Portal\Config;

/**
 * Login brake, per (network address + mobile number): 6 wrong tries in 10 minutes -> wait.
 * Kept in small files under storage/throttle so it works on any shared hosting without a database.
 * (The API has its own brake per address; behind one hosting address that would lock everyone out together, so this one is
 * per person and is checked first.)
 */
final class Throttle
{
    private const MAX = 6;
    private const WINDOW = 600;

    private static function file(string $key): string
    {
        return Config::path('storage/throttle/' . hash('sha256', $key) . '.json');
    }

    private static function read(string $key): array
    {
        $f = self::file($key);
        $a = is_file($f) ? json_decode((string) @file_get_contents($f), true) : [];
        $now = time();
        return array_values(array_filter(is_array($a) ? $a : [], fn ($t) => is_int($t) && $now - $t < self::WINDOW));
    }

    /** Seconds to wait, or 0 when a try is allowed. */
    public static function wait(string $key): int
    {
        $a = self::read($key);
        if (count($a) < self::MAX) {
            return 0;
        }
        return max(1, self::WINDOW - (time() - min($a)));
    }

    public static function fail(string $key): void
    {
        $a = self::read($key);
        $a[] = time();
        @file_put_contents(self::file($key), json_encode($a), LOCK_EX);
    }

    public static function clear(string $key): void
    {
        @unlink(self::file($key));
    }
}
