<?php
declare(strict_types=1);

namespace Portal\Http\Middleware;

use Portal\Auth\Session;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface as Handler;
use Slim\Psr7\Response as SlimResponse;

/** Signed-in people only. Optionally also a permission (the API checks it again on every call). */
final class RequireAuth implements MiddlewareInterface
{
    public function __construct(private ?string $permission = null)
    {
    }

    public function process(Request $request, Handler $handler): Response
    {
        if (!Session::check()) {
            if ($request->getMethod() === 'GET' && $request->getHeaderLine('HX-Request') === '') {
                Session::intended($request->getUri()->getPath() . ($request->getUri()->getQuery() ? '?' . $request->getUri()->getQuery() : ''));
            }
            return self::redirect($request, '/login');
        }
        if ($this->permission !== null && !Session::can($this->permission)) {
            $r = new SlimResponse(403);
            $r->getBody()->write('You do not have permission to open this page.');
            return $r;
        }
        return $handler->handle($request);
    }

    public static function redirect(Request $request, string $to): Response
    {
        $r = new SlimResponse(302);
        if ($request->getHeaderLine('HX-Request') !== '') {
            return $r->withStatus(200)->withHeader('HX-Redirect', $to);   // a partial cannot follow a redirect: tell the browser to go
        }
        return $r->withHeader('Location', $to);
    }
}
