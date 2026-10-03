<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Support\Nav;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Views\Twig;

/** Menu pages that are planned but not built yet: a friendly page instead of an error. */
final class PageController
{
    public function soon(Request $request, Response $response): Response
    {
        $path = $request->getUri()->getPath();
        $found = null;
        foreach (Nav::forUser() as $g) {
            foreach ($g['items'] as $it) {
                if (rtrim($it['href'], '/') === rtrim($path, '/')) {
                    $found = $it;
                }
            }
        }
        if ($found === null) {
            $r = $response->withStatus(404);
            return Twig::fromRequest($request)->render($r, 'errors/404.twig', ['active' => '']);
        }
        return Twig::fromRequest($request)->render($response, 'soon.twig', ['item' => $found, 'active' => $found['key']]);
    }
}
