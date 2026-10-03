<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Portal\Auth\Session;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/**
 * GST bills: the list, one bill (view / print / payments / returns) and the new-bill form.
 * Every figure comes from the server (POST /billing/calculate): the portal only shows it and never does bill maths itself.
 */
final class BillingController extends BaseController
{
    private const MODES = ['Cash', 'Online', 'Card', 'Cheque'];
    private const PURITIES = ['24K', '22K', '18K', '14K', '999', '925', '800'];
    private const PAGE = 20;

    // ── list ──────────────────────────────────────────────────────────────────────────────────

    public function index(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'billing/index.twig', ['active' => 'billing']);
    }

    public function list(Request $rq, Response $rs): Response
    {
        $status = $this->q($rq, 'status');
        $q = $this->q($rq, 'q');
        $page = max(1, (int) $this->q($rq, 'page', '1'));
        $from = $this->q($rq, 'from');
        $to = $this->q($rq, 'to');
        $params = array_filter([
            'q' => $q, 'status' => in_array($status, ['due', 'paid'], true) ? $status : '', 'page' => $page, 'limit' => self::PAGE,
            'from' => preg_match('/^\d{4}-\d{2}-\d{2}$/', $from) ? $from : '', 'to' => preg_match('/^\d{4}-\d{2}-\d{2}$/', $to) ? $to : '',
        ], fn ($v) => $v !== '');
        $r = $this->api()->get('billing/invoices', $params);
        return $this->view($rq, $rs, 'billing/list.twig', [
            'rows' => $r['data'] ?? [], 'pg' => $r['pagination'] ?? [], 'status' => $status, 'q' => $q, 'page' => $page, 'from' => $from, 'to' => $to,
            'more' => $this->isHx($rq) && $page > 1,
        ]);
    }

    // ── one bill ──────────────────────────────────────────────────────────────────────────────

    public function show(Request $rq, Response $rs, array $args): Response
    {
        $id = rawurlencode($args['id']);
        $r = $this->api()->get("billing/invoices/$id");
        $notes = [];
        if (Session::can('billing.view')) {
            try {
                $notes = (array) ($this->api()->get("credit-notes/invoice/$id")['data']['notes'] ?? []);
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        return $this->view($rq, $rs, 'billing/show.twig', ['inv' => $r['data'] ?? [], 'notes' => $notes, 'active' => 'billing']);
    }

    /** A clean page laid out like the paper tax invoice, to print or save as PDF. */
    public function print(Request $rq, Response $rs, array $args): Response
    {
        $id = rawurlencode($args['id']);
        $r = $this->api()->get("billing/invoices/$id");
        $type = 'ORIGINAL';
        try {
            $type = (string) ($this->api()->post("billing/invoices/$id/print", [])['data']['printType'] ?? 'ORIGINAL');
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'billing/print.twig', ['printType' => $type, 'inv' => $r['data'] ?? [], 'seller' => $r['seller'] ?? [], 'terms' => $r['terms'] ?? [], 'declaration' => $r['declaration'] ?? '']);
    }

    // ── returns / refunds (credit notes) ─────────────────────────────────────────────────────

    public function returnForm(Request $rq, Response $rs, array $args): Response
    {
        $st = $this->api()->get('credit-notes/invoice/' . rawurlencode($args['id']))['data'] ?? [];
        return $this->view($rq, $rs, 'billing/return.twig', ['id' => $args['id'], 'st' => $st, 'modes' => self::MODES, 'v' => [], 'error' => null, 'rid' => $this->requestId('cn')]);
    }

    public function returnPreview(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        $lines = $this->returnLines($b);
        $prev = null;
        $err = null;
        if ($lines) {
            try {
                $prev = $this->api()->post('credit-notes/preview', ['invoiceId' => $args['id'], 'lines' => $lines], 10)['data'] ?? null;
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
                $err = $e->getMessage();
            }
        }
        return $this->view($rq, $rs, 'billing/return_total.twig', ['prev' => $prev, 'err' => $err]);
    }

    public function returnSave(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        $lines = $this->returnLines($b);
        try {
            $this->api()->post('credit-notes', [
                'requestId' => (string) ($b['rid'] ?? '') ?: $this->requestId('cn'), 'invoiceId' => $args['id'], 'lines' => $lines,
                'reason' => (string) ($b['reason'] ?? 'sales_return'), 'note' => (string) ($b['note'] ?? ''),
                'refundMode' => (string) ($b['refundMode'] ?? ''), 'refundAmount' => (float) ($b['refundAmount'] ?? 0), 'restock' => !empty($b['restock']),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $st = $this->api()->get('credit-notes/invoice/' . rawurlencode($args['id']))['data'] ?? [];
            return $this->view($rq, $rs->withStatus(422), 'billing/return.twig', ['id' => $args['id'], 'st' => $st, 'modes' => self::MODES, 'v' => $b, 'error' => $e->getMessage(), 'rid' => (string) ($b['rid'] ?? '')]);
        }
        return $this->refreshWith($rs, 'success', 'Credit note saved');
    }

    /** Ticked lines with the amount (before tax) to take back. */
    private function returnLines(array $b): array
    {
        $out = [];
        foreach ((array) ($b['ret'] ?? []) as $i => $row) {
            $row = (array) $row;
            if (!empty($row['on']) && (float) ($row['taxable'] ?? 0) > 0) {
                $out[] = ['index' => (int) $i, 'taxable' => (float) $row['taxable']];
            }
        }
        return $out;
    }

    // ── new bill ──────────────────────────────────────────────────────────────────────────────

    public function newForm(Request $rq, Response $rs): Response
    {
        $meta = $this->api()->get('billing/meta')['data'] ?? [];
        $v = [
            'goldRate' => $meta['goldRate'] ?? '', 'silverRate' => $meta['silverRate'] ?? '', 'placeOfSupply' => $meta['defaultPlace'] ?? '',
            'invoiceDate' => $meta['today'] ?? date('Y-m-d'), 'items' => [], 'payments' => [['mode' => 'Cash', 'amount' => ''], ['mode' => 'Online', 'amount' => '']],
        ];
        $note = '';
        // deliver a made-to-order piece: customer and description come from the order, its advance is taken off the bill
        $orderId = $this->q($rq, 'order');
        if ($orderId !== '' && self::isId($orderId)) {
            $o = [];
            try {
                $o = $this->api()->get('orders/' . rawurlencode($orderId))['data'] ?? [];
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
                $note = 'That order could not be found.';
            }
            if ($o) {
                $v['orderId'] = $orderId;
                $v['orderAdvance'] = (float) ($o['advancePaid'] ?? 0);
                $v['customerId'] = $o['customerId'] ?? '';
                $v['customerName'] = $o['customerName'] ?? '';
                $v['customerMobile'] = $o['customerMobile'] ?? '';
                $v['items'][] = ['particulars' => $o['description'] ?? '', 'metalType' => ucfirst((string) ($o['metalType'] ?? 'gold')), 'purity' => $o['purity'] ?? '', 'netWt' => $o['approxWeight'] ?? ''];
                $note = 'Order ' . ($o['number'] ?? '') . ': the advance of ' . \Portal\Support\Money::inr($o['advancePaid'] ?? 0) . ' is taken off this bill. Put in the real weight.';
            }
        }
        // a bill for a saved customer: name, mobile and address come from the directory
        $custId = $this->q($rq, 'customer');
        if ($custId !== '' && self::isId($custId)) {
            try {
                $c = $this->api()->get('directory/customers/' . rawurlencode($custId))['data'] ?? [];
                if ($c) {
                    $v['customerId'] = $custId;
                    $v['customerName'] = $c['customer_name'] ?? '';
                    $v['customerMobile'] = $c['whatsapp_no'] ?: ($c['mobile_no'] ?? '');
                    $v['customerAddress'] = $c['address'] ?? '';
                    $v['customerPan'] = $c['profile']['panNo'] ?? '';
                }
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        // sell one stock piece: it comes pre-filled and priced by the shop's rules
        $code = $this->q($rq, 'item');
        if ($code !== '') {
            try {
                $line = $this->api()->get('billing/stock-line', ['code' => $code, 'goldRate' => $v['goldRate'], 'silverRate' => $v['silverRate']])['data'] ?? [];
                if ($line) {
                    $v['items'][] = self::fromApiItem($line);
                }
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
                $note = $e->getMessage();
            }
        }
        // make the bill from an estimate (same items, today's rates)
        $estId = $this->q($rq, 'estimate');
        if ($estId !== '' && self::isId($estId)) {
            $e = [];
            try {
                $e = $this->api()->get('estimates/' . rawurlencode($estId))['data'] ?? [];
            } catch (ApiException $ex) {
                $this->rethrowIfSystem($ex);
                $note = 'That estimate could not be found.';
            }
            if ($e && ($e['status'] ?? '') === 'open') {
                $v['estimateId'] = $estId;
                $v['customerId'] = $e['customerId'] ?? '';
                $v['customerName'] = $e['customerName'] ?? '';
                $v['customerMobile'] = $e['customerMobile'] ?? '';
                $v['items'] = array_map([self::class, 'fromApiItem'], (array) ($e['inputItems'] ?? []));
                $v['additionalCharges'] = $e['additionalCharges'] ?? '';
                $note = 'From estimate ' . ($e['number'] ?? '') . '. Check the rates and the discount, then add the payment.';
            }
        }
        return $this->form($rq, $rs, 'bill', $meta, $v, null, $note);
    }

    /** One more empty item row (the "Add item" button). */
    public function row(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'billing/row.twig', ['k' => bin2hex(random_bytes(4)), 'it' => [], 'purities' => self::PURITIES]);
    }

    /** A stock piece by barcode as a filled row: priced by the shop's Stock Setting rules on the server. */
    public function stockRow(Request $rq, Response $rs): Response
    {
        $code = $this->q($rq, 'code');
        if ($code === '') {
            return $this->toast($rs, 'error', 'Type or scan the barcode');
        }
        try {
            $it = $this->api()->get('billing/stock-line', ['code' => $code, 'goldRate' => $this->q($rq, 'goldRate'), 'silverRate' => $this->q($rq, 'silverRate')])['data'] ?? [];
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        $st = (float) ($it['extras'][0]['amount'] ?? 0);
        $it['stoneAmount'] = $st > 0 ? $st : '';
        $it['stoneName'] = $it['extras'][0]['name'] ?? '';
        $it['stoneWt'] = ($it['extras'][0]['weight'] ?? 0) > 0 ? $it['extras'][0]['weight'] : '';
        return $this->view($rq, $rs, 'billing/row.twig', ['k' => bin2hex(random_bytes(4)), 'it' => $it, 'purities' => self::PURITIES])
            ->withHeader('HX-Trigger', json_encode(['stock-added' => true]));
    }

    /** The stock search under the item box: pieces that match a name or barcode, to add with one click. */
    public function stockSearch(Request $rq, Response $rs): Response
    {
        $q = $this->q($rq, 'code');
        $rows = [];
        if (mb_strlen($q) >= 2) {
            try {
                $rows = (array) ($this->api()->get('items', ['search' => $q, 'status' => 'active', 'limit' => 8])['data']['items'] ?? []);
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        return $this->view($rq, $rs, 'billing/stock_hits.twig', ['rows' => $rows, 'q' => $q]);
    }

    /** A saved customer for a 10-digit mobile number (the bill fills the name, address, PAN and state by itself). */
    public function customerByMobile(Request $rq, Response $rs): Response
    {
        $out = ['found' => false];
        $m = preg_replace('/\D/', '', $this->q($rq, 'mobile'));
        if (strlen($m) >= 10) {
            $m = substr($m, -10);
            try {
                $hits = (array) ($this->api()->get('directory/customers/lookup', ['q' => $m])['data'] ?? []);
                $hit = null;
                foreach ($hits as $h) {
                    if (!empty($h['exact'])) {
                        $hit = $h;
                        break;
                    }
                }
                if ($hit) {
                    $id = (string) $hit['id'];
                    $c = (array) ($this->api()->get('directory/customers/' . rawurlencode($id))['data'] ?? []);
                    $sum = (array) ($this->api()->get('billing/customer/' . rawurlencode($id))['data'] ?? []);
                    $out = ['found' => true, 'id' => $id, 'name' => $c['customer_name'] ?? ($hit['name'] ?? ''), 'address' => $c['address'] ?? '', 'pan' => $c['profile']['panNo'] ?? '', 'place' => $sum['place'] ?? '', 'due' => $sum['totalDue'] ?? 0];
                }
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        $rs->getBody()->write(json_encode($out));
        return $rs->withHeader('Content-Type', 'application/json');
    }

    /** How much cash can still be taken today from this customer (s.269ST), for the payment box. */
    public function cashRoom(Request $rq, Response $rs): Response
    {
        $d = ['limit' => 200000, 'alreadyToday' => 0, 'room' => 199999];
        try {
            $d = (array) ($this->api()->get('billing/cash-today', array_filter(['customerId' => $this->q($rq, 'customerId'), 'mobile' => $this->q($rq, 'mobile')], fn ($v) => $v !== ''))['data'] ?? $d);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        $rs->getBody()->write(json_encode($d));
        return $rs->withHeader('Content-Type', 'application/json');
    }

    /** The totals box next to the form, worked out by the server while the person types. */
    public function calc(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        $items = $this->items($b);
        $calc = null;
        $err = null;
        if ($items) {
            try {
                $calc = $this->api()->post('billing/calculate', $this->payload($b, $items), 10)['data'] ?? null;
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
                $err = $e->getMessage();
            }
        }
        return $this->view($rq, $rs, 'billing/totals.twig', ['c' => $calc, 'err' => $err, 'asked' => $items !== [], 'mode' => (string) ($b['mode'] ?? 'bill'), 'keys' => $this->itemKeys($b)]);
    }

    /** The customer's unused old metal, to tick off against this bill. */
    public function oldMetal(Request $rq, Response $rs): Response
    {
        $rows = [];
        $name = $this->q($rq, 'customerName');
        $mobile = $this->q($rq, 'customerMobile');
        $key = $mobile !== '' && strlen(preg_replace('/\D/', '', $mobile)) >= 10 ? $mobile : $name;
        if (mb_strlen($key) >= 2) {
            try {
                $all = (array) ($this->api()->get('old-metal', ['kind' => 'old', 'used' => 'no', 'q' => $key])['data']['rows'] ?? []);
                $rows = array_values(array_filter($all, fn ($o) => ($o['kind'] ?? '') === 'old'));
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        return $this->view($rq, $rs, 'billing/oldmetal.twig', ['rows' => $rows]);
    }

    public function create(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        $items = $this->items($b);
        $body = $this->payload($b, $items) + [
            'requestId' => (string) ($b['rid'] ?? '') ?: $this->requestId('inv'),
            'customerId' => (string) ($b['customerId'] ?? ''), 'customerName' => (string) ($b['customerName'] ?? ''), 'customerMobile' => (string) ($b['customerMobile'] ?? ''),
            'customerAddress' => (string) ($b['customerAddress'] ?? ''), 'customerPan' => (string) ($b['customerPan'] ?? ''),
            'invoiceDate' => (string) ($b['invoiceDate'] ?? ''), 'note' => (string) ($b['note'] ?? ''),
        ];
        try {
            $r = $this->api()->post('billing/invoices', $body, 30);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $meta = $this->api()->get('billing/meta')['data'] ?? [];
            return $this->form($rq, $rs->withStatus(422), 'bill', $meta, $this->keep($b), $e->getMessage(), '');
        }
        $inv = $r['data'] ?? [];
        if (!empty($b['estimateId']) && self::isId((string) $b['estimateId'])) {
            try {
                $this->api()->post('estimates/' . rawurlencode((string) $b['estimateId']) . '/converted', ['invoiceNumber' => (string) ($inv['invoiceNumber'] ?? '')]);
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        $this->flash('success', 'Bill ' . ($inv['invoiceNumber'] ?? '') . ' saved');
        return $this->redirect($rs, '/billing/' . rawurlencode((string) ($inv['_id'] ?? '')));
    }

    // ── helpers shared with estimates ─────────────────────────────────────────────────────────

    public static function isId(string $s): bool
    {
        return preg_match('/^[0-9a-f]{24}$/i', $s) === 1;
    }

    /** The same rows the form sent, in the shape the API expects. Rows left empty are ignored. */
    public function items(array $b): array
    {
        $out = [];
        foreach ((array) ($b['items'] ?? []) as $r) {
            $r = (array) $r;
            $name = trim((string) ($r['particulars'] ?? ''));
            $net = trim((string) ($r['netWt'] ?? ''));
            if ($name === '' && $net === '') {
                continue;
            }
            $it = [
                'particulars' => $name, 'metalType' => (string) ($r['metalType'] ?? 'Gold'), 'purity' => (string) ($r['purity'] ?? ''), 'netWt' => $net,
                'grossWt' => (string) ($r['grossWt'] ?? ''), 'rate' => (string) ($r['rate'] ?? ''), 'makingCharge' => (string) ($r['makingCharge'] ?? ''),
                'hsnCode' => (string) ($r['hsnCode'] ?? ''), 'taxableOverride' => (string) ($r['taxableOverride'] ?? ''),
                'certification' => (string) ($r['certification'] ?? ''), 'huid' => (string) ($r['huid'] ?? ''), 'hallmarkCharge' => (string) ($r['hallmarkCharge'] ?? ''),
                'productCode' => (string) ($r['productCode'] ?? ''), 'itemId' => (string) ($r['itemId'] ?? ''),
            ];
            if ((float) ($r['stoneAmount'] ?? 0) > 0 || (float) ($r['stoneWt'] ?? 0) > 0) {
                $it['extras'] = [['kind' => 'Stone', 'name' => (string) ($r['stoneName'] ?? ''), 'weight' => (float) ($r['stoneWt'] ?? 0), 'amount' => (float) ($r['stoneAmount'] ?? 0)]];
            }
            $out[] = $it;
        }
        return $out;
    }

    /** The form keys of the rows that count (not empty), in the same order as `items()`: used to put each line's amount back on its row. */
    private function itemKeys(array $b): array
    {
        $out = [];
        foreach ((array) ($b['items'] ?? []) as $k => $r) {
            $r = (array) $r;
            if (trim((string) ($r['particulars'] ?? '')) !== '' || trim((string) ($r['netWt'] ?? '')) !== '') {
                $out[] = (string) $k;
            }
        }
        return $out;
    }

    /** An item as the API stores it back to a form row. */
    public static function fromApiItem(array $i): array
    {
        $ex = (array) (($i['extras'] ?? [])[0] ?? []);
        return [
            'particulars' => $i['particulars'] ?? $i['particular'] ?? '', 'metalType' => $i['metalType'] ?? 'Gold', 'purity' => $i['purity'] ?? '', 'netWt' => $i['netWt'] ?? '',
            'grossWt' => $i['grossWt'] ?? '', 'rate' => $i['rate'] ?? '', 'makingCharge' => $i['makingCharge'] ?? '', 'hsnCode' => $i['hsnCode'] ?? '',
            'taxableOverride' => $i['taxableOverride'] ?? '', 'certification' => $i['certification'] ?? '', 'huid' => $i['huid'] ?? '', 'hallmarkCharge' => $i['hallmarkCharge'] ?? '',
            'productCode' => $i['productCode'] ?? '', 'itemId' => $i['itemId'] ?? '', 'stoneAmount' => $ex['amount'] ?? '', 'stoneName' => $ex['name'] ?? '', 'stoneWt' => $ex['weight'] ?? '',
        ];
    }

    private function payload(array $b, array $items): array
    {
        $pays = [];
        foreach ((array) ($b['payments'] ?? []) as $p) {
            $p = (array) $p;
            if ((float) ($p['amount'] ?? 0) > 0) {
                $pays[] = ['mode' => (string) ($p['mode'] ?? 'Cash'), 'amount' => (float) $p['amount'], 'reference' => (string) ($p['reference'] ?? '')];
            }
        }
        return [
            'items' => $items, 'goldRate' => (string) ($b['goldRate'] ?? ''), 'silverRate' => (string) ($b['silverRate'] ?? ''),
            'placeOfSupply' => (string) ($b['placeOfSupply'] ?? ''), 'additionalCharges' => (string) ($b['additionalCharges'] ?? ''), 'discount' => (string) ($b['discount'] ?? ''),
            'payments' => $pays, 'oldMetalIds' => array_values(array_filter((array) ($b['oldMetalIds'] ?? []), 'is_string')), 'orderId' => (string) ($b['orderId'] ?? ''),
        ];
    }

    /** The form values again after an error, so nothing typed is lost. */
    private function keep(array $b): array
    {
        $b['items'] = array_values((array) ($b['items'] ?? []));
        $b['payments'] = array_values((array) ($b['payments'] ?? []));
        return $b;
    }

    private function form(Request $rq, Response $rs, string $mode, array $meta, array $v, ?string $error, string $note): Response
    {
        if (empty($v['items'])) {
            $v["items"] = [[]];
        }
        if (empty($v['payments'])) {
            $v['payments'] = [['mode' => 'Cash', 'amount' => ''], ['mode' => 'Online', 'amount' => '']];
        }
        return $this->view($rq, $rs, 'billing/new.twig', [
            'mode' => $mode, 'meta' => $meta, 'v' => $v, 'error' => $error, 'note' => $note, 'modes' => self::MODES, 'purities' => self::PURITIES,
            'rid' => (string) ($v['rid'] ?? '') ?: $this->requestId($mode === 'bill' ? 'inv' : 'est'), 'active' => $mode === 'bill' ? 'billing' : 'estimates',
        ]);
    }

    /** Estimates use the same form in "quote" mode (no payment, no old metal, valid for some days). */
    public function estimateForm(Request $rq, Response $rs): Response
    {
        $meta = $this->api()->get('billing/meta')['data'] ?? [];
        return $this->form($rq, $rs, 'estimate', $meta, ['goldRate' => $meta['goldRate'] ?? '', 'silverRate' => $meta['silverRate'] ?? '', 'validDays' => 7, 'items' => []], null, '');
    }

    public function estimateCreate(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        $items = $this->items($b);
        try {
            $r = $this->api()->post('estimates', [
                'requestId' => (string) ($b['rid'] ?? '') ?: $this->requestId('est'), 'customerId' => (string) ($b['customerId'] ?? ''),
                'customerName' => (string) ($b['customerName'] ?? ''), 'customerMobile' => (string) ($b['customerMobile'] ?? ''),
                'items' => $items, 'goldRate' => (string) ($b['goldRate'] ?? ''), 'silverRate' => (string) ($b['silverRate'] ?? ''),
                'additionalCharges' => (string) ($b['additionalCharges'] ?? ''), 'discount' => (string) ($b['discount'] ?? ''),
                'validDays' => (int) ($b['validDays'] ?? 7), 'note' => (string) ($b['note'] ?? ''),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $meta = $this->api()->get('billing/meta')['data'] ?? [];
            return $this->form($rq, $rs->withStatus(422), 'estimate', $meta, $this->keep($b), $e->getMessage(), '');
        }
        $this->flash('success', 'Estimate ' . ($r['data']['number'] ?? '') . ' saved');
        return $this->redirect($rs, '/estimates/' . rawurlencode((string) ($r['data']['id'] ?? '')));
    }
}
