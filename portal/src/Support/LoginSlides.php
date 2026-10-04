<?php
declare(strict_types=1);

namespace Portal\Support;

use Portal\Api\ApiClient;
use Portal\Config;

/**
 * The pictures of the sign-in page: the same ones the app shows on its own sign-in screen (Admin Control > Login screen),
 * 4:5 portrait. Read from the API (public, no sign-in needed) and kept in a small file for a few minutes, so the sign-in page
 * does not wait for the API; if the API cannot be reached the last list is used (or none: the page then shows a plain colour).
 */
final class LoginSlides
{
    private const TTL = 300;

    /** @return array<int,array{imageUrl:string,captionEn:string,captionBn:string}> */
    public static function all(): array
    {
        $file = Config::path('storage/login-slides.json');
        $cached = is_file($file) ? json_decode((string) @file_get_contents($file), true) : null;
        if (is_array($cached) && isset($cached['at'], $cached['slides']) && time() - (int) $cached['at'] < self::TTL) {
            return (array) $cached['slides'];
        }
        try {
            $r = (new ApiClient())->get('app-assets/login-slides', [], 3);
            $slides = array_values(array_filter((array) ($r['data']['slides'] ?? []), static fn ($s) => is_array($s) && preg_match('#^https?://#', (string) ($s['imageUrl'] ?? '')) === 1));
            @file_put_contents($file, json_encode(['at' => time(), 'slides' => $slides]));
            return $slides;
        } catch (\Throwable $e) {
            return is_array($cached) ? (array) ($cached['slides'] ?? []) : [];
        }
    }
}
