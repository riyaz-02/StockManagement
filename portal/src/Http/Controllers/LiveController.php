<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Portal\Auth\Session;
use Portal\Config;
use Portal\Http\Api;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/**
 * Live updates for the open page. The browser never holds the login token: it asks here for a one-time 60-second ticket
 * and opens the live stream of the API with it. It also lets the page re-read the person's permissions after they change.
 */
final class LiveController
{
    public function ticket(Request $request, Response $response): Response
    {
        try {
            $r = Api::client()->post('live/ticket', [], 10);
            return $this->json($response, ['ticket' => $r['data']['ticket'] ?? '', 'url' => Config::publicApiBase() . '/api/live']);
        } catch (ApiException $e) {
            return $this->json($response->withStatus($e->unauthorized() ? 401 : 503), ['error' => $e->getMessage()]);
        }
    }

    /** Re-read this person's permissions from the API (after an admin changed them) and keep the session in step. */
    public function refresh(Request $request, Response $response): Response
    {
        try {
            $me = Api::client()->get('permissions/me');
            Session::updatePermissions((array) ($me['data']['permissions'] ?? []), ($me['data']['all'] ?? false) === true);
            return $this->json($response, ['ok' => true]);
        } catch (ApiException $e) {
            return $this->json($response->withStatus($e->unauthorized() ? 401 : 503), ['error' => $e->getMessage()]);
        }
    }

    /** A small heartbeat from the open page ("I'm here, on this screen") for Staff & Roles > Live now. Best-effort. */
    public function ping(Request $request, Response $response): Response
    {
        $b = (array) ($request->getParsedBody() ?? []);
        try {
            Api::client()->post('presence/ping', ['platform' => 'web', 'screen' => substr((string) ($b['screen'] ?? ''), 0, 60)], 5);
        } catch (ApiException $e) {
            // a missed heartbeat is not worth failing the page over
        }
        return $this->json($response, ['ok' => true]);
    }

    private function json(Response $response, array $data): Response
    {
        $response->getBody()->write(json_encode($data));
        return $response->withHeader('Content-Type', 'application/json');
    }
}
