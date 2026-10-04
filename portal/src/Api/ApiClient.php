<?php
declare(strict_types=1);

namespace Portal\Api;

use Portal\Config;

/**
 * The portal's only door to the data: the Node API (the same one the phone app uses).
 * Rules, permissions and branch scope are enforced there, never here.
 */
final class ApiClient
{
    public function __construct(private ?string $token = null, private string $branch = '')
    {
    }

    public function withToken(?string $token, string $branch = ''): self
    {
        $c = clone $this;
        $c->token = $token;
        $c->branch = $branch;
        return $c;
    }

    /** @return array the decoded JSON envelope (success, data, ...) */
    public function get(string $path, array $query = [], int $timeout = 25): array
    {
        return $this->request('GET', $path, $query, null, $timeout);
    }

    public function post(string $path, array $body = [], int $timeout = 40): array
    {
        return $this->request('POST', $path, [], $body, $timeout);
    }

    public function put(string $path, array $body = [], int $timeout = 40): array
    {
        return $this->request('PUT', $path, [], $body, $timeout);
    }

    public function patch(string $path, array $body = [], int $timeout = 40): array
    {
        return $this->request('PATCH', $path, [], $body, $timeout);
    }

    public function delete(string $path, int $timeout = 25): array
    {
        return $this->request('DELETE', $path, [], null, $timeout);
    }

    /**
     * POST one file (and a few plain fields) to the API as multipart/form-data. Used to hand an uploaded APK from the
     * browser to the API: the file is streamed from PHP's temp file, never held in memory.
     * @return array the decoded JSON envelope
     */
    public function upload(string $path, string $field, string $filePath, string $fileName, array $fields = [], int $timeout = 3600, string $mime = 'application/vnd.android.package-archive'): array
    {
        $ch = curl_init(Config::apiBase() . '/api/' . ltrim($path, '/'));
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $fields + [$field => new \CURLFile($filePath, $mime, $fileName)],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_HTTPHEADER => $this->baseHeaders(),
        ]);
        $raw = curl_exec($ch);
        try {
            return $this->finish($ch, is_string($raw) ? $raw : '', true);
        } finally {
            curl_close($ch);
        }
    }

    /**
     * Several GETs at once: a dashboard needs 4-5 numbers, this makes it as slow as the slowest call, not the sum.
     * @param array<string,array{0:string,1?:array}> $calls key => [path, query]
     * @return array<string,array|ApiException> each result, or the exception of that call
     */
    public function multi(array $calls, int $timeout = 25): array
    {
        $mh = curl_multi_init();
        $handles = [];
        foreach ($calls as $key => $c) {
            $ch = $this->handle('GET', $c[0], $c[1] ?? [], null, $timeout);
            $handles[$key] = $ch;
            curl_multi_add_handle($mh, $ch);
        }
        do {
            $status = curl_multi_exec($mh, $running);
            if ($running) {
                curl_multi_select($mh, 1.0);
            }
        } while ($running && $status === CURLM_OK);
        $out = [];
        foreach ($handles as $key => $ch) {
            $raw = curl_multi_getcontent($ch);
            $out[$key] = $this->finish($ch, is_string($raw) ? $raw : '', false);
            curl_multi_remove_handle($mh, $ch);
            curl_close($ch);
        }
        curl_multi_close($mh);
        return $out;
    }

    /** Is the server ready (its databases connected)? 'online' | 'starting' | 'offline' */
    public static function health(int $timeout = 4): string
    {
        $ch = curl_init(Config::apiBase() . '/health');
        curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => $timeout, CURLOPT_CONNECTTIMEOUT => min(3, $timeout), CURLOPT_HTTPHEADER => ['Accept: application/json']]);
        $raw = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
        if (!is_string($raw)) {
            return 'offline';
        }
        $j = json_decode($raw, true);
        if ($code === 200) {
            return is_array($j) && ($j['ready'] ?? true) === false ? 'starting' : 'online';
        }
        if ($code === 503 && is_array($j) && ($j['status'] ?? '') === 'starting') {
            return 'starting';
        }
        return 'offline';
    }

    private function request(string $method, string $path, array $query, ?array $body, int $timeout): array
    {
        $ch = $this->handle($method, $path, $query, $body, $timeout);
        $raw = curl_exec($ch);
        try {
            return $this->finish($ch, is_string($raw) ? $raw : '', true);
        } finally {
            curl_close($ch);
        }
    }

    /**
     * POST to the API and hand its answer straight to the browser as a file download, piece by piece: a backup can be big, so
     * it is never held in memory. If the API refuses BEFORE any file byte (wrong password, nothing chosen...) this throws an
     * ApiException and nothing has been sent, so the page can still show the reason.
     * @return int bytes of the file sent
     */
    public function download(string $path, array $body, int $timeout = 7200): int
    {
        $status = 0;
        $ctype = '';
        $disp = '';
        $sent = 0;
        $started = false;
        $err = '';
        $ch = curl_init(Config::apiBase() . '/api/' . ltrim($path, '/'));
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_HTTPHEADER => array_merge($this->baseHeaders(), ['Content-Type: application/json']),
            CURLOPT_HEADERFUNCTION => function ($c, string $line) use (&$status, &$ctype, &$disp): int {
                if (stripos($line, 'HTTP/') === 0) {
                    $status = (int) substr($line, 9, 3);
                    $ctype = '';
                    $disp = '';
                } elseif (stripos($line, 'content-type:') === 0) {
                    $ctype = trim(substr($line, 13));
                } elseif (stripos($line, 'content-disposition:') === 0) {
                    $disp = trim(substr($line, 20));
                }
                return strlen($line);
            },
            CURLOPT_WRITEFUNCTION => function ($c, string $chunk) use (&$status, &$ctype, &$disp, &$sent, &$started, &$err): int {
                if ($status === 200 && stripos($ctype, 'application/zip') === 0) {
                    if (!$started) {
                        $started = true;
                        @set_time_limit(0);
                        if (session_status() === PHP_SESSION_ACTIVE) {
                            session_write_close();   // a long download must not hold the session lock and freeze the person's other tabs
                        }
                        while (ob_get_level() > 0) {
                            ob_end_clean();
                        }
                        @ini_set('zlib.output_compression', '0');
                        header('Content-Type: application/zip');
                        header('Content-Disposition: ' . ($disp !== '' ? $disp : 'attachment; filename="backup.zip"'));
                        header('Cache-Control: no-store');
                        header('X-Content-Type-Options: nosniff');
                    }
                    echo $chunk;
                    flush();
                    $sent += strlen($chunk);
                } elseif (strlen($err) < 65536) {
                    $err .= $chunk;   // an error answer is small JSON: keep it to explain the refusal
                }
                return strlen($chunk);
            },
        ]);
        curl_exec($ch);
        $curlError = curl_error($ch);
        curl_close($ch);
        if (!$started) {
            $j = json_decode($err, true);
            $message = is_array($j) && isset($j['message']) ? (string) $j['message']
                : ($curlError !== '' ? 'The server did not answer: ' . $curlError : 'The server sent an unexpected answer (' . $status . ')');
            throw new ApiException($message, $status > 0 ? $status : 0, is_array($j) ? $j : []);
        }
        if ($curlError !== '') {
            error_log('[portal] a download from the API stopped part-way: ' . $curlError);   // the browser gets a cut-off file and shows it as failed
        }
        return $sent;
    }

    /** The headers every call to the API carries: who is asking, for which branch, and which visitor (for its login limiter). */
    private function baseHeaders(): array
    {
        $headers = ['Accept: application/json'];
        if ($this->token) {
            $headers[] = 'Authorization: Bearer ' . $this->token;
        }
        if ($this->branch !== '') {
            $headers[] = 'X-Branch: ' . $this->branch;
        }
        // tell the API which visitor this is (its login limiter counts per person, not per website address); it trusts this only with the shared secret
        $secret = Config::get('PORTAL_SHARED_KEY');
        if ($secret !== '' && !empty($_SERVER['REMOTE_ADDR'])) {
            $headers[] = 'X-Portal-Key: ' . $secret;
            $headers[] = 'X-Portal-Client-Ip: ' . $_SERVER['REMOTE_ADDR'];
        }
        return $headers;
    }

    private function handle(string $method, string $path, array $query, ?array $body, int $timeout)
    {
        $url = Config::apiBase() . '/api/' . ltrim($path, '/');
        if ($query) {
            $url .= '?' . http_build_query($query);
        }
        $headers = $this->baseHeaders();
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_ENCODING => '',
        ]);
        if ($body !== null) {
            $headers[] = 'Content-Type: application/json';
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        }
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        return $ch;
    }

    private function finish($ch, string $raw, bool $throw): array|ApiException
    {
        $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $err = curl_error($ch);
        $fail = null;
        if ($code === 0 || $raw === '') {
            $fail = new ApiException($err !== '' ? 'The server did not answer: ' . $err : 'The server did not answer', 0);
        } else {
            $j = json_decode($raw, true);
            if (!is_array($j)) {
                // an HTML error page from a proxy (502 Bad Gateway ...) or anything that is not our API
                $fail = new ApiException('The server sent an unexpected answer (' . $code . ')', $code === 200 ? 502 : $code);
            } elseif ($code >= 400 || ($j['success'] ?? true) === false) {
                $fail = new ApiException((string) ($j['message'] ?? ('Request failed (' . $code . ')')), $code >= 400 ? $code : 400, $j);
            } else {
                return $j;
            }
        }
        if ($throw) {
            throw $fail;
        }
        return $fail;
    }
}
