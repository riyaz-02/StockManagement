<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Support\Wake;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Views\Twig;

/** The "Starting the server..." screen: it wakes the backend, then sends the person on when it is ready. */
final class WakeController
{
    /** Only same-site paths are allowed as the place to go next. */
    public static function safeNext(?string $next): string
    {
        return is_string($next) && str_starts_with($next, '/') && !str_starts_with($next, '//') && !str_contains($next, '\\') ? $next : '/';
    }

    public function page(Request $request, Response $response): Response
    {
        $next = self::safeNext($request->getQueryParams()['next'] ?? '/');
        if (Wake::status() === 'online') {
            return $response->withHeader('Location', $next)->withStatus(302);
        }
        return Twig::fromRequest($request)->render($response, 'wake.twig', ['next' => $next]);
    }

    public function status(Request $request, Response $response): Response
    {
        return $this->json($response, ['state' => Wake::status()]);
    }

    public function start(Request $request, Response $response): Response
    {
        $state = Wake::status();
        $did = $state === 'offline' ? Wake::start() : ['sent' => false, 'reason' => 'already ' . $state];
        return $this->json($response, ['state' => $state] + $did);
    }

    private function json(Response $response, array $data): Response
    {
        $response->getBody()->write(json_encode($data));
        return $response->withHeader('Content-Type', 'application/json');
    }
}
