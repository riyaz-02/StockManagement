<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Made-to-order pieces: what was asked for, the advance, who is making it, and when it is due. */
final class OrderController extends BaseController
{
    private const MODES = ['Cash', 'Online', 'Card', 'Cheque'];

    public function index(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'orders/index.twig', ['active' => 'orders']);
    }

    public function list(Request $rq, Response $rs): Response
    {
        $status = $this->q($rq, 'status', 'active');
        $q = $this->q($rq, 'q');
        $r = $this->api()->get('orders', array_filter(['status' => $status, 'q' => $q], fn ($v) => $v !== ''));
        return $this->view($rq, $rs, 'orders/list.twig', ['rows' => $r['data'] ?? [], 'counts' => $r['counts'] ?? [], 'status' => $status, 'q' => $q]);
    }

    public function newForm(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'orders/new.twig', ['active' => 'orders', 'v' => ['metalType' => 'gold', 'purity' => '22K', 'advanceMode' => 'Cash', 'deliveryDate' => date('Y-m-d', strtotime('+15 days'))], 'error' => null, 'modes' => self::MODES, 'rid' => $this->requestId('ord')]);
    }

    public function create(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        try {
            $r = $this->api()->post('orders', [
                'requestId' => (string) ($b['rid'] ?? '') ?: $this->requestId('ord'),
                'customerId' => (string) ($b['customerId'] ?? ''), 'customerName' => (string) ($b['customerName'] ?? ''), 'customerMobile' => (string) ($b['customerMobile'] ?? ''),
                'description' => (string) ($b['description'] ?? ''), 'metalType' => (string) ($b['metalType'] ?? 'gold'), 'purity' => (string) ($b['purity'] ?? ''),
                'approxWeight' => (string) ($b['approxWeight'] ?? ''), 'estimatedPrice' => (string) ($b['estimatedPrice'] ?? ''), 'deliveryDate' => (string) ($b['deliveryDate'] ?? ''),
                'advanceAmount' => (string) ($b['advanceAmount'] ?? ''), 'advanceMode' => (string) ($b['advanceMode'] ?? 'Cash'), 'karigar' => (string) ($b['karigar'] ?? ''), 'note' => (string) ($b['note'] ?? ''),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->view($rq, $rs->withStatus(422), 'orders/new.twig', ['active' => 'orders', 'v' => $b, 'error' => $e->getMessage(), 'modes' => self::MODES, 'rid' => (string) ($b['rid'] ?? '')]);
        }
        $this->flash('success', 'Order ' . ($r['data']['number'] ?? '') . ' saved.');
        return $this->redirect($rs, '/orders/' . rawurlencode((string) ($r['data']['id'] ?? '')));
    }

    public function show(Request $rq, Response $rs, array $args): Response
    {
        $o = $this->api()->get('orders/' . rawurlencode($args['id']))['data'] ?? [];
        return $this->view($rq, $rs, 'orders/show.twig', ['active' => 'orders', 'o' => $o]);
    }

    public function advanceForm(Request $rq, Response $rs, array $args): Response
    {
        $o = $this->api()->get('orders/' . rawurlencode($args['id']))['data'] ?? [];
        return $this->view($rq, $rs, 'orders/advance.twig', ['o' => $o, 'modes' => self::MODES, 'v' => ['mode' => 'Cash'], 'error' => null]);
    }

    public function advance(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        $id = rawurlencode($args['id']);
        try {
            $this->api()->post("orders/$id/advance", ['amount' => (string) ($b['amount'] ?? ''), 'mode' => (string) ($b['mode'] ?? 'Cash')]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $o = $this->api()->get("orders/$id")['data'] ?? [];
            return $this->view($rq, $rs->withStatus(422), 'orders/advance.twig', ['o' => $o, 'modes' => self::MODES, 'v' => $b, 'error' => $e->getMessage()]);
        }
        return $this->refreshWith($rs, 'success', 'Advance saved.');
    }

    public function status(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->post('orders/' . rawurlencode($args['id']) . '/status', ['status' => (string) ($b['status'] ?? ''), 'karigar' => $b['karigar'] ?? null] + []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $this->refreshWith($rs, 'success', ($b['status'] ?? '') === 'ready' ? 'Marked ready. Call the customer.' : 'Marked as being made.');
    }

    public function cancelForm(Request $rq, Response $rs, array $args): Response
    {
        $o = $this->api()->get('orders/' . rawurlencode($args['id']))['data'] ?? [];
        return $this->view($rq, $rs, 'orders/cancel.twig', ['o' => $o, 'modes' => self::MODES, 'v' => ['refundMode' => 'Cash', 'refundAmount' => $o['advancePaid'] ?? ''], 'error' => null]);
    }

    public function cancel(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        $id = rawurlencode($args['id']);
        try {
            $this->api()->post("orders/$id/cancel", ['refundMode' => (string) ($b['refundMode'] ?? 'Cash'), 'refundAmount' => (string) ($b['refundAmount'] ?? ''), 'reason' => (string) ($b['reason'] ?? '')]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $o = $this->api()->get("orders/$id")['data'] ?? [];
            return $this->view($rq, $rs->withStatus(422), 'orders/cancel.twig', ['o' => $o, 'modes' => self::MODES, 'v' => $b, 'error' => $e->getMessage()]);
        }
        return $this->refreshWith($rs, 'success', 'Order cancelled.');
    }
}
