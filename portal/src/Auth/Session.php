<?php
declare(strict_types=1);

namespace Portal\Auth;

use Portal\Config;

/**
 * The signed-in person. The API token lives here, on the server (PHP session), never in the browser's JavaScript.
 * Permissions are exactly what the API says for this user (GET /api/permissions/me), so the menu can hide what
 * the API would refuse. The API still checks every call itself.
 */
final class Session
{
    public static function start(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            return;
        }
        $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
        session_name(Config::get('PORTAL_SESSION_NAME', 'lgp_portal'));
        session_set_cookie_params(['lifetime' => 0, 'path' => '/', 'secure' => $https, 'httponly' => true, 'samesite' => 'Lax']);
        ini_set('session.use_strict_mode', '1');
        ini_set('session.use_only_cookies', '1');
        session_start();
        // idle timeout: a forgotten screen signs itself out
        $idle = max(5, (int) Config::get('PORTAL_IDLE_MINUTES', '480')) * 60;
        if (isset($_SESSION['last']) && time() - (int) $_SESSION['last'] > $idle) {
            self::logout();
            session_start();
            $_SESSION['flash'] = ['type' => 'info', 'text' => 'You were signed out because the page was idle for a long time.'];
        }
        $_SESSION['last'] = time();
    }

    public static function login(array $user, string $token, array $perms, bool $all): void
    {
        session_regenerate_id(true);
        $_SESSION['user'] = $user;
        $_SESSION['token'] = $token;
        $_SESSION['perms'] = $perms;
        $_SESSION['all'] = $all;
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
        $_SESSION['last'] = time();
    }

    /** After an admin changed this person's access: keep the session in step without a new login. */
    public static function updatePermissions(array $perms, bool $all): void
    {
        $_SESSION['perms'] = $perms;
        $_SESSION['all'] = $all;
    }

    public static function logout(): void
    {
        $_SESSION = [];
        if (ini_get('session.use_cookies')) {
            $p = session_get_cookie_params();
            setcookie(session_name(), '', ['expires' => time() - 3600, 'path' => $p['path'], 'secure' => $p['secure'], 'httponly' => true, 'samesite' => 'Lax']);
        }
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_destroy();
        }
    }

    public static function check(): bool
    {
        return isset($_SESSION['user'], $_SESSION['token']);
    }

    public static function user(): array
    {
        return $_SESSION['user'] ?? [];
    }

    public static function token(): ?string
    {
        return $_SESSION['token'] ?? null;
    }

    /** Admin / owner pass every check (the API says so with all=true). */
    public static function can(string $key): bool
    {
        if (!self::check()) {
            return false;
        }
        return ($_SESSION['all'] ?? false) === true || (($_SESSION['perms'] ?? [])[$key] ?? false) === true;
    }

    public static function isAdmin(): bool
    {
        return in_array(self::user()['role'] ?? '', ['admin', 'owner'], true);
    }

    public static function csrf(): string
    {
        if (empty($_SESSION['csrf'])) {
            $_SESSION['csrf'] = bin2hex(random_bytes(32));
        }
        return $_SESSION['csrf'];
    }

    public static function flash(?array $set = null): ?array
    {
        if ($set !== null) {
            $_SESSION['flash'] = $set;
            return null;
        }
        $f = $_SESSION['flash'] ?? null;
        unset($_SESSION['flash']);
        return $f;
    }

    public static function intended(?string $set = null): ?string
    {
        if ($set !== null) {
            $_SESSION['intended'] = $set;
            return null;
        }
        $v = $_SESSION['intended'] ?? null;
        unset($_SESSION['intended']);
        return $v;
    }

    public static function branch(): string
    {
        return (string) ($_SESSION['branch'] ?? '');
    }

    public static function setBranch(string $id): void
    {
        $_SESSION['branch'] = $id;
    }
}
