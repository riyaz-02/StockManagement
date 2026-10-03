<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Portal\Auth\Session;
use Portal\Http\Api;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Views\Twig;

/** Today's gold / silver rate: the strip at the top of every page, and the small form that changes it. */
final class RateController
{
    public function strip(Request $request, Response $response): Response
    {
        $rate = [];
        try {
            $rate = (array) (Api::client()->get('rates')['data'] ?? []);
        } catch (ApiException $e) {
            if ($e->unauthorized() || $e->down()) {
                throw $e;
            }
        }
        return Twig::fromRequest($request)->render($response, 'partials/rate_strip.twig', ['rate' => $rate, 'can_edit' => Session::can('rates.edit')]);
    }

    public function form(Request $request, Response $response): Response
    {
        $rate = (array) (Api::client()->get('rates')['data'] ?? []);
        return Twig::fromRequest($request)->render($response, 'partials/rate_form.twig', ['rate' => $rate, 'error' => null]);
    }

    public function save(Request $request, Response $response): Response
    {
        $b = (array) $request->getParsedBody();
        $body = [];
        foreach (['gold', 'silver'] as $k) {
            $v = trim((string) ($b[$k] ?? ''));
            if ($v !== '') {
                $body[$k] = (float) $v;
            }
        }
        $view = Twig::fromRequest($request);
        try {
            Api::client()->put('rates', $body);
        } catch (ApiException $e) {
            if ($e->unauthorized() || $e->down()) {
                throw $e;
            }
            return $view->render($response->withStatus(422), 'partials/rate_form.twig', ['rate' => $b, 'error' => $e->getMessage()]);
        }
        // close the dialog, refresh the strip everywhere, tell the person
        return $response->withStatus(204)
            ->withHeader('HX-Trigger', json_encode(['rate-saved' => true, 'toast' => ['type' => 'success', 'text' => 'Rate saved']]));
    }
}
