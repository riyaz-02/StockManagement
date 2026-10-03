<?php
declare(strict_types=1);

namespace Portal\Support;

use Portal\Api\ApiClient;
use Portal\Config;

/**
 * The backend runs only when the app or this website needs it (it stops itself when idle, to save money).
 * This starts it with the same start-up function the phone app uses, and reports when it is ready.
 */
final class Wake
{
    public static function status(): string
    {
        return ApiClient::health();
    }

    /** Ask the start-up function to start the server. At most once per minute. Returns what was done. */
    public static function start(): array
    {
        $url = Config::get('PORTAL_WAKE_URL');
        if ($url === '') {
            return ['sent' => false, 'reason' => 'no wake address is configured (development)'];
        }
        $f = Config::path('storage/wake.json');
        $last = is_file($f) ? (int) (json_decode((string) @file_get_contents($f), true)['at'] ?? 0) : 0;
        if (time() - $last < 60) {
            return ['sent' => false, 'reason' => 'already asked a moment ago'];
        }
        @file_put_contents($f, json_encode(['at' => time()]), LOCK_EX);
        $ch = curl_init($url);
        // the start-up function can take a while to answer: we only need to have asked, the page keeps checking /health
        curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 8, CURLOPT_CONNECTTIMEOUT => 5]);
        curl_exec($ch);
        curl_close($ch);
        return ['sent' => true];
    }
}
