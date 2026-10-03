<?php
declare(strict_types=1);

namespace Portal\Api;

/** An API call that did not succeed. down() = the server did not answer properly (asleep, starting, proxy error). */
final class ApiException extends \RuntimeException
{
    public function __construct(string $message, public readonly int $status = 0, public readonly array $body = [])
    {
        parent::__construct($message, $status);
    }

    /** No usable answer: connection failed, or a proxy/gateway error (502/503/504). */
    public function down(): bool
    {
        return $this->status === 0 || in_array($this->status, [502, 503, 504], true);
    }

    public function unauthorized(): bool
    {
        return $this->status === 401;
    }

    public function forbidden(): bool
    {
        return $this->status === 403;
    }
}
