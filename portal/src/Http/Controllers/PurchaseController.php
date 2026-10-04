<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Metal bought from suppliers: the list, one purchase, and adding one (GST, input credit and TDS are worked out by the server). */
final class PurchaseController extends BaseController
{
    private const PAGE = 20;
    private const PURITIES = ['24K', '22K', '18K', '14K', '999', '925', '800'];

    public function index(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'purchases/index.twig', ['active' => 'purchases']);
    }

    public function list(Request $rq, Response $rs): Response
    {
        $metal = $this->q($rq, 'metal');
        $q = $this->q($rq, 'q');
        $page = max(1, (int) $this->q($rq, 'page', '1'));
        $range = ['from' => $this->q($rq, 'from'), 'to' => $this->q($rq, 'to')];
        $ok = fn (string $d) => preg_match('/^\d{4}-\d{2}-\d{2}$/', $d) === 1;
        $params = array_filter([
            'metalType' => $metal, 'biller' => $q, 'page' => $page, 'limit' => self::PAGE,
            'startDate' => $ok($range['from']) ? $range['from'] : '', 'endDate' => $ok($range['to']) ? $range['to'] : '',
        ], fn ($v) => $v !== '');
        $d = $this->api()->get('purchases', $params)['data'] ?? [];
        $pg = $d['pagination'] ?? [];
        $pg['hasMore'] = ($pg['page'] ?? 1) < ($pg['pages'] ?? 1);
        return $this->view($rq, $rs, 'purchases/list.twig', [
            'rows' => $d['purchases'] ?? [], 'pg' => $pg, 'totals' => $d['metalTotals'] ?? [], 'metal' => $metal, 'q' => $q, 'page' => $page, 'from' => $range['from'], 'to' => $range['to'],
            'more' => $this->isHx($rq) && $page > 1,
        ]);
    }

    public function show(Request $rq, Response $rs, array $args): Response
    {
        $p = $this->api()->get('purchases/' . rawurlencode($args['id']))['data']['purchase'] ?? [];
        return $this->view($rq, $rs, 'purchases/show.twig', ['p' => $p, 'active' => 'purchases']);
    }

    public function newForm(Request $rq, Response $rs): Response
    {
        return $this->form($rq, $rs, ['invoiceDate' => date('Y-m-d'), 'metalType' => 'gold', 'purity' => '22K', 'transactionType' => 'intra-state'], null);
    }

    public function calc(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        $c = null;
        $err = null;
        $body = $this->body($b);
        if ((float) ($body['quantity'] ?? 0) > 0 || isset($body['valuation']) || (float) ($body['totalAmount'] ?? 0) > 0) {
            try {
                $c = $this->api()->post('purchases/calculate', $body, 10)['data'] ?? null;
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
                $err = $e->getMessage();
            }
        }
        return $this->view($rq, $rs, 'purchases/totals.twig', ['c' => $c, 'err' => $err]);
    }

    public function create(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        try {
            $r = $this->api()->post('purchases', $this->body($b) + [
                'invoiceDate' => (string) ($b['invoiceDate'] ?? ''), 'invoiceNumber' => (string) ($b['invoiceNumber'] ?? ''),
                'biller' => (string) ($b['biller'] ?? ''), 'billerGstin' => (string) ($b['billerGstin'] ?? ''), 'description' => (string) ($b['description'] ?? ''),
                'remarks' => (string) ($b['remarks'] ?? ''),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->form($rq, $rs->withStatus(422), $b, $e->getMessage());
        }
        $p = $r['data']['purchase'] ?? $r['data'] ?? [];
        $this->flash('success', 'Purchase saved');
        return $this->redirect($rs, '/purchases/' . rawurlencode((string) ($p['_id'] ?? '')));
    }

    public function remove(Request $rq, Response $rs, array $args): Response
    {
        try {
            $this->api()->delete('purchases/' . rawurlencode($args['id']));
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        $this->flash('success', 'Purchase removed');
        return $rs->withStatus(204)->withHeader('HX-Redirect', '/purchases');
    }

    /** The numbers part of the form as the API wants it: either weight x rate, or the weights worked out by the Purchase rules. */
    private function body(array $b): array
    {
        $out = ['metalType' => strtolower((string) ($b['metalType'] ?? 'gold')), 'transactionType' => (string) ($b['transactionType'] ?? 'intra-state')];
        if (!empty($b['useValuation'])) {
            $out['valuation'] = [
                'gross' => (string) ($b['vGross'] ?? ''), 'less' => (string) ($b['vLess'] ?? ''), 'net' => (string) ($b['vNet'] ?? ''), 'purity' => (string) ($b['purity'] ?? ''),
                'wastage' => (string) ($b['vWastage'] ?? ''), 'rate' => (string) ($b['vRate'] ?? ''), 'labourRate' => (string) ($b['vLabour'] ?? ''),
                'pieces' => (string) ($b['vPieces'] ?? '1'), 'certification' => (string) ($b['vCert'] ?? ''),
            ];
            $out['quantity'] = (string) ($b['vNet'] ?? '');
            $out['rate'] = (string) ($b['vRate'] ?? '');
        } else {
            $out['quantity'] = (string) ($b['quantity'] ?? '');
            $out['rate'] = (string) ($b['rate'] ?? '');
            if (trim((string) ($b['totalAmount'] ?? '')) !== '') {
                $out['totalAmount'] = (string) $b['totalAmount'];
            }
        }
        // the supplier's invoice total as printed (it can differ from the worked-out total by a round-off)
        if (trim((string) ($b['invoiceTotal'] ?? '')) !== '') {
            $out['invoiceTotal'] = (string) $b['invoiceTotal'];
        }
        return $out;
    }

    /** Correct the invoice total of a saved purchase (the supplier's round-off). GST and input credit do not change. */
    public function total(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->put('purchases/' . rawurlencode($args['id']), ['invoiceTotal' => trim((string) ($b['invoiceTotal'] ?? ''))]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        $this->flash('success', 'Invoice total updated');
        return $rs->withStatus(204)->withHeader('HX-Redirect', '/purchases/' . rawurlencode($args['id']));
    }

    private function form(Request $rq, Response $rs, array $v, ?string $error): Response
    {
        $sug = [];
        try {
            $sug = (array) ($this->api()->get('purchases/suggestions')['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'purchases/form.twig', ['v' => $v, 'error' => $error, 'sug' => $sug, 'purities' => self::PURITIES, 'active' => 'purchases']);
    }
}
