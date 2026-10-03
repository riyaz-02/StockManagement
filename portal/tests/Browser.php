<?php
declare(strict_types=1);

date_default_timezone_set('Asia/Kolkata');   // the shop's day, same as the portal and the API

/** A tiny browser: keeps cookies between calls, does not follow redirects. */
final class Browser
{
    private string $jar;
    public function __construct(private string $base)
    {
        $this->jar = tempnam(sys_get_temp_dir(), 'pj');
    }
    public function __destruct()
    {
        @unlink($this->jar);
    }
    /** @return array{code:int,headers:array,body:string} */
    public function req(string $method, string $path, array $form = [], array $headers = []): array
    {
        $ch = curl_init($this->base . $path);
        $out = [];
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST => $method, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 30, CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_COOKIEJAR => $this->jar, CURLOPT_COOKIEFILE => $this->jar,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_HEADERFUNCTION => function ($c, $line) use (&$out) {
                if (str_contains($line, ':')) { [$k, $v] = explode(':', $line, 2); $out[strtolower(trim($k))] = trim($v); }
                return strlen($line);
            },
        ]);
        if ($form) { curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($form)); }
        $body = (string) curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
        return ['code' => $code, 'headers' => $out, 'body' => $body];
    }
    public function csrf(string $path = '/login'): string
    {
        $r = $this->req('GET', $path);
        return preg_match('/<meta name="csrf" content="([a-f0-9]+)"/', $r['body'], $m) ? $m[1] : '';
    }
    public function login(string $mobile, string $password): array
    {
        return $this->req('POST', '/login', ['_csrf' => $this->csrf(), 'mobile' => $mobile, 'password' => $password]);
    }
}
