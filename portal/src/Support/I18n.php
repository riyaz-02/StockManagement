<?php
declare(strict_types=1);

namespace Portal\Support;

use Portal\Config;

/** Words on screen. English first; a second language is just another file in /lang (bn.php) with the same keys. */
final class I18n
{
    private static array $words = [];
    private static array $fallback = [];
    public static string $lang = 'en';

    public static function load(string $lang): void
    {
        self::$lang = preg_match('/^[a-z]{2}$/', $lang) ? $lang : 'en';
        self::$fallback = self::file('en');
        self::$words = self::$lang === 'en' ? self::$fallback : array_replace(self::$fallback, self::file(self::$lang));
    }

    private static function file(string $lang): array
    {
        $f = Config::path("lang/$lang.php");
        return is_file($f) ? (array) require $f : [];
    }

    public static function t(string $key, array $vars = []): string
    {
        $s = self::$words[$key] ?? self::$fallback[$key] ?? $key;
        foreach ($vars as $k => $v) {
            $s = str_replace('{' . $k . '}', (string) $v, $s);
        }
        return $s;
    }
}
