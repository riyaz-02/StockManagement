<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Portal\Auth\Session;
use Portal\Http\Api;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Views\Twig;

final class HomeController
{
    /** The page shell: paints at once; the numbers arrive by themselves through /partials/dashboard. */
    public function index(Request $request, Response $response): Response
    {
        return Twig::fromRequest($request)->render($response, 'home.twig', ['flash' => Session::flash(), 'active' => 'home']);
    }

    /** Today's numbers, loaded in parallel from the API. A card the person may not see, or that fails, is simply left out. */
    public function stats(Request $request, Response $response): Response
    {
        $today = date('Y-m-d');
        $calls = [];
        if (Session::can('billing.view')) {
            $calls['sales'] = ['billing/stats', ['from' => $today, 'to' => $today]];
            $calls['dues'] = ['billing/dues'];
        }
        if (Session::can('daybook.view')) {
            $calls['book'] = ['billing/daybook', ['from' => $today, 'to' => $today]];
        }
        if (Session::can('orders.view')) {
            $calls['orders'] = ['orders', ['status' => 'active']];
        }
        $res = $calls ? Api::client()->multi($calls) : [];
        // a signed-out token or a sleeping server must be handled by the page, not hidden
        foreach ($res as $r) {
            if ($r instanceof ApiException && ($r->unauthorized() || $r->down())) {
                throw $r;
            }
        }
        $ok = fn (string $k) => isset($res[$k]) && is_array($res[$k]) ? ($res[$k]['data'] ?? null) : null;
        $orders = isset($res['orders']) && is_array($res['orders']) ? ($res['orders']['counts'] ?? null) : null;
        return Twig::fromRequest($request)->render($response, 'partials/dashboard.twig', [
            'sales' => $ok('sales'),
            'dues' => $ok('dues'),
            'book' => $ok('book'),
            'orders' => $orders,
        ]);
    }
}
