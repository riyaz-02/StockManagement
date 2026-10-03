<?php
declare(strict_types=1);

namespace Portal\Http\Middleware;

use Portal\Auth\Csrf;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface as Handler;
use Slim\Psr7\Response as SlimResponse;

/** Anything that changes data must carry the session's secret token (form field _csrf, or the X-CSRF-Token header for HTMX). */
final class CsrfGuard implements MiddlewareInterface
{
    public function process(Request $request, Handler $handler): Response
    {
        if (in_array($request->getMethod(), ['POST', 'PUT', 'PATCH', 'DELETE'], true)) {
            $body = $request->getParsedBody();
            $sent = $request->getHeaderLine('X-CSRF-Token') ?: (is_array($body) ? ($body['_csrf'] ?? null) : null);
            if (!Csrf::valid(is_string($sent) ? $sent : null)) {
                $r = new SlimResponse(419);
                $r->getBody()->write('Your page expired. Please reload and try again.');
                return $r;
            }
        }
        return $handler->handle($request);
    }
}
