<?php
declare(strict_types=1);

namespace Portal\Auth;

/** Every form and every HTMX request that changes something carries this token; a foreign site cannot know it. */
final class Csrf
{
    public static function valid(?string $sent): bool
    {
        return is_string($sent) && $sent !== '' && hash_equals(Session::csrf(), $sent);
    }
}
