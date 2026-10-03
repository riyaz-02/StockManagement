<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Price quotes: the list, one quote (view / print / make the bill / cancel). Making one uses the same form as a bill. */
final class EstimateController extends BaseController
{
    public function index(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'estimates/index.twig', ['active' => 'estimates']);
    }

    public function list(Request $rq, Response $rs): Response
    {
        $status = $this->q($rq, 'status');
        $q = $this->q($rq, 'q');
        $rows = $this->api()->get('estimates', array_filter(['status' => $status, 'q' => $q], fn ($v) => $v !== ''))['data'] ?? [];
        return $this->view($rq, $rs, 'estimates/list.twig', ['rows' => $rows, 'status' => $status, 'q' => $q]);
    }

    public function show(Request $rq, Response $rs, array $args): Response
    {
        $e = $this->api()->get('estimates/' . rawurlencode($args['id']))['data'] ?? [];
        return $this->view($rq, $rs, 'estimates/show.twig', ['e' => $e, 'active' => 'estimates']);
    }

    public function print(Request $rq, Response $rs, array $args): Response
    {
        $r = $this->api()->get('estimates/' . rawurlencode($args['id']));
        $seller = $this->api()->get('billing/meta')['data']['seller'] ?? [];
        return $this->view($rq, $rs, 'estimates/print.twig', ['e' => $r['data'] ?? [], 'seller' => $seller]);
    }

    public function cancel(Request $rq, Response $rs, array $args): Response
    {
        try {
            $this->api()->delete('estimates/' . rawurlencode($args['id']));
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $this->refreshWith($rs, 'success', 'Estimate cancelled');
    }
}
