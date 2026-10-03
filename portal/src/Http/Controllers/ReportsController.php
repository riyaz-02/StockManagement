<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Portal\Auth\Session;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** One page that answers "how is the shop doing": stock position, today's movement, this month's sales and what is owed. */
final class ReportsController extends BaseController
{
    public function index(Request $rq, Response $rs): Response
    {
        $get = function (string $path, array $q = []) {
            try {
                return (array) ($this->api()->get($path, $q)['data'] ?? []);
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
                return [];
            }
        };
        $from = date('Y-m-01');
        $to = date('Y-m-d');
        $sales = Session::can('gst.viewReports') ? $get('gst-reports/summary', ['gstin' => '', 'from' => $from, 'to' => $to]) : [];
        return $this->view($rq, $rs, 'reports/index.twig', [
            'stock' => $get('analytics/dashboard'), 'today' => $get('reports/daily'), 'sales' => $sales,
            'dues' => Session::can('billing.view') ? $get('billing/dues') : [], 'from' => $from, 'to' => $to, 'active' => 'reports',
        ]);
    }
}
