<?php
declare(strict_types=1);

namespace Portal;

use Portal\Api\ApiException;
use Portal\Auth\Session;
use Portal\Http\Controllers\WakeController;
use Psr\Http\Message\ResponseFactoryInterface;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Exception\HttpNotFoundException;
use Slim\Views\Twig;

/**
 * One place that turns a failure into the right screen:
 * server asleep -> the "Starting the server" page, session ended -> login, no permission -> a clear message,
 * anything else -> a plain error page (with the detail only in development).
 */
final class ErrorHandler
{
    public function __construct(private ResponseFactoryInterface $responses, private ?Twig $twig = null)
    {
    }

    public function __invoke(Request $request, \Throwable $e, bool $displayErrorDetails): Response
    {
        $hx = $request->getHeaderLine('HX-Request') !== '';
        $path = $request->getUri()->getPath();

        if ($e instanceof ApiException) {
            if ($e->down()) {
                $to = '/wake?next=' . rawurlencode($hx ? ($request->getHeaderLine('HX-Current-URL') ? parse_url($request->getHeaderLine('HX-Current-URL'), PHP_URL_PATH) ?: '/' : '/') : $path);
                return $this->go($hx, $to);
            }
            if ($e->unauthorized()) {
                Session::logout();
                session_start();
                Session::flash(['type' => 'info', 'text' => 'Please sign in again.']);
                return $this->go($hx, '/login');
            }
            if ($e->forbidden()) {
                return $this->page($request, 403, 'errors/403.twig', ['message' => $e->getMessage()]);
            }
            return $this->page($request, 502, 'errors/500.twig', ['message' => $e->getMessage(), 'detail' => Config::isDev() ? $e->getMessage() : '']);
        }
        if ($e instanceof HttpNotFoundException) {
            return $this->page($request, 404, 'errors/404.twig', ['active' => '']);
        }
        error_log('[portal] ' . get_class($e) . ': ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
        return $this->page($request, 500, 'errors/500.twig', ['message' => 'Something went wrong on our side.', 'detail' => Config::isDev() ? $e->getMessage() . ' (' . basename($e->getFile()) . ':' . $e->getLine() . ')' : '']);
    }

    private function go(bool $hx, string $to): Response
    {
        $r = $this->responses->createResponse($hx ? 200 : 302);
        return $hx ? $r->withHeader('HX-Redirect', $to) : $r->withHeader('Location', $to);
    }

    private function page(Request $request, int $status, string $template, array $data = []): Response
    {
        $r = $this->responses->createResponse($status);
        try {
            // an unknown address fails in routing, before the view middleware ran: use the view given at start-up
            $twig = $request->getAttribute('__twigView') ? Twig::fromRequest($request) : ($this->twig ?? Twig::fromRequest($request));
            if ($request->getHeaderLine('HX-Request') !== '') {
                // inside a page: a small notice, not a whole new page
                $r->getBody()->write('<div class="notice notice-error">' . htmlspecialchars((string) ($data['message'] ?? 'Something went wrong.'), ENT_QUOTES) . '</div>');
                return $r->withStatus(200)->withHeader('HX-Retarget', '#toasts')->withHeader('HX-Reswap', 'beforeend');
            }
            return $twig->render($r, $template, $data + ['active' => '']);
        } catch (\Throwable) {
            $r->getBody()->write('Error ' . $status);
            return $r;
        }
    }
}
