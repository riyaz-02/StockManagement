<?php
declare(strict_types=1);

namespace Portal;

/** Settings from the .env file next to composer.json (kept outside the public folder). */
final class Config
{
    private static array $v = [];
    public static string $root = '';

    public static function load(string $root): void
    {
        self::$root = rtrim($root, '/\\');
        $file = self::$root . '/.env';
        if (is_file($file)) {
            foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
                $line = trim($line);
                if ($line === '' || $line[0] === '#' || !str_contains($line, '=')) {
                    continue;
                }
                [$k, $val] = explode('=', $line, 2);
                $val = trim(preg_replace('/\s+#.*$/', '', $val));
                self::$v[trim($k)] = trim($val, " \t\"'");
            }
        }
    }

    public static function get(string $key, string $default = ''): string
    {
        // a real environment variable wins over the .env file (handy for tests and for hosting panels)
        $env = getenv($key);
        return $env !== false && $env !== '' ? (string) $env : (self::$v[$key] ?? $default);
    }

    public static function isDev(): bool
    {
        return self::get('PORTAL_ENV', 'prod') === 'dev';
    }

    public static function apiBase(): string
    {
        return rtrim(self::get('PORTAL_API_BASE', 'http://localhost:5000'), '/');
    }

    /** The address the BROWSER uses for the live stream (defaults to the server-side address; differs only in special set-ups). */
    public static function publicApiBase(): string
    {
        $v = self::get('PORTAL_API_PUBLIC', '');
        return $v !== '' ? rtrim($v, '/') : self::apiBase();
    }

    public static function path(string $rel): string
    {
        return self::$root . '/' . ltrim($rel, '/');
    }
}
