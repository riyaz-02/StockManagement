<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Portal\Auth\Session;
use Portal\Http\Api;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Views\Twig;

/** The bell in the top bar: how many things need a look, and the list (notices that were sent + reminders that are open now). */
final class BellController
{
    /** @return array{items: array, unread: int, reminders: int} */
    private function feed(): array
    {
        try {
            $d = (array) (Api::client()->get('notifications/feed', ['limit' => 30], 10)['data'] ?? []);
        } catch (ApiException $e) {
            if ($e->unauthorized() || $e->down()) {
                throw $e;
            }
            $d = [];
        }
        return $d + ['items' => [], 'unread' => 0, 'reminders' => 0];
    }

    /** The red number on the bell. */
    public function count(Request $request, Response $response): Response
    {
        $f = $this->feed();
        return Twig::fromRequest($request)->render($response, 'partials/bell_count.twig', ['n' => (int) $f['unread']]);
    }

    /** The drop-down list. */
    public function list(Request $request, Response $response): Response
    {
        $f = $this->feed();
        $items = array_map(function (array $i): array {
            // where a tap goes on the website
            $i['href'] = match ((string) ($i['link'] ?? '')) {
                'gst' => Session::can('gst.viewReports') ? '/gst' : '',
                'tally' => Session::can('tally.view') ? '/tally' : '',
                'update' => Session::can('appUpdate.manage') ? '/admin/updates' : '',
                default => '',
            };
            return $i;
        }, (array) $f['items']);
        return Twig::fromRequest($request)->render($response, 'partials/bell_list.twig', ['items' => $items, 'unread' => (int) $f['unread']]);
    }

    /** Opening the list counts the notices as read; the number on the bell is refreshed. */
    public function seen(Request $request, Response $response): Response
    {
        try {
            Api::client()->post('notifications/feed/seen', [], 10);
        } catch (ApiException $e) {
            if ($e->unauthorized() || $e->down()) {
                throw $e;
            }
        }
        return $response->withStatus(204)->withHeader('HX-Trigger', 'bell-refresh');
    }
}
