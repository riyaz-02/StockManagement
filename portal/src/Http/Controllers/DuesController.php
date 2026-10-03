<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Who still owes the shop money, biggest first, and receiving a payment on a bill. */
final class DuesController extends BaseController
{
    private const MODES = ['Cash', 'Online', 'Card', 'Cheque'];

    public function index(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'dues/index.twig', ['active' => 'dues']);
    }

    public function list(Request $rq, Response $rs): Response
    {
        $q = $this->q($rq, 'q');
        $d = $this->api()->get('billing/dues', $q !== '' ? ['q' => $q] : [])['data'] ?? [];
        return $this->view($rq, $rs, 'dues/list.twig', ['d' => $d, 'q' => $q]);
    }

    public function payForm(Request $rq, Response $rs, array $args): Response
    {
        $inv = $this->api()->get('billing/invoices/' . rawurlencode($args['id']))['data'] ?? [];
        return $this->view($rq, $rs, 'dues/pay.twig', ['inv' => $inv, 'modes' => self::MODES, 'v' => ['amount' => $inv['dueAmount'] ?? '', 'mode' => 'Cash'], 'error' => null, 'rid' => $this->requestId('pay')]);
    }

    public function pay(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        $id = rawurlencode($args['id']);
        try {
            $this->api()->post("billing/invoices/$id/payments", [
                'requestId' => (string) ($b['rid'] ?? '') ?: $this->requestId('pay'),
                'amount' => (float) ($b['amount'] ?? 0), 'mode' => (string) ($b['mode'] ?? 'Cash'), 'reference' => (string) ($b['reference'] ?? ''),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $inv = $this->api()->get("billing/invoices/$id")['data'] ?? [];
            return $this->view($rq, $rs->withStatus(422), 'dues/pay.twig', ['inv' => $inv, 'modes' => self::MODES, 'v' => $b, 'error' => $e->getMessage(), 'rid' => (string) ($b['rid'] ?? '')]);
        }
        return $this->done($rs, 'Payment received');
    }
}
