<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Stock pieces: the list, one piece, add / edit, and the small actions (no-sell, put back, remove). Prices come from the server. */
final class StockController extends BaseController
{
    private const PAGE = 25;
    private const OTHER = 'booked,no_sell,temporarily_removed,action_needed,repair,in_repair,UNDER_REPAIR,WITH_CUSTOMER,WITH_AGENT';
    private const STATUS_TEXT = [
        'active' => ['In stock', 'green'], 'sold' => ['Sold', 'grey'], 'booked' => ['Booked', 'blue'], 'no_sell' => ['Not for sale', 'amber'],
        'temporarily_removed' => ['Taken out', 'amber'], 'action_needed' => ['Needs details', 'red'], 'repair' => ['In repair', 'amber'],
        'in_repair' => ['In repair', 'amber'], 'UNDER_REPAIR' => ['In repair', 'amber'], 'WITH_CUSTOMER' => ['With customer', 'blue'], 'WITH_AGENT' => ['With agent', 'blue'], 'deleted' => ['Removed', 'grey'],
    ];

    /** The kinds of bulk stock (metal kept together without a barcode), as the API names them. */
    private const KINDS = ['dust' => 'Dust / filings', 'parts' => 'Parts', 'sub_items' => 'Sub items', 'raw' => 'Raw metal', 'in_process' => 'In process', 'reserved' => 'Reserved', 'other' => 'Other'];
    private const METALS = ['gold' => 'Gold', 'silver' => 'Silver', 'platinum' => 'Platinum', 'other' => 'Other'];

    public function index(Request $rq, Response $rs): Response
    {
        $dash = [];
        try {
            $dash = (array) ($this->api()->get('stock/dashboard')['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'stock/index.twig', ['dash' => $dash, 'active' => 'stock']);
    }

    public function list(Request $rq, Response $rs): Response
    {
        $tab = $this->q($rq, 'tab', 'in');
        $metal = $this->q($rq, 'metal');
        $q = $this->q($rq, 'q');
        $page = max(1, (int) $this->q($rq, 'page', '1'));
        $status = ['in' => 'active', 'sold' => 'sold', 'other' => self::OTHER, 'all' => ''][$tab] ?? 'active';
        $r = $this->api()->get('items', array_filter(['status' => $status, 'metalType' => $metal, 'search' => $q, 'page' => $page, 'limit' => self::PAGE], fn ($v) => $v !== ''));
        return $this->view($rq, $rs, 'stock/list.twig', [
            'rows' => $r['data']['items'] ?? [], 'pg' => $r['pagination'] ?? [], 'totals' => $r['totals'] ?? [], 'tab' => $tab, 'metal' => $metal, 'q' => $q, 'page' => $page,
            'more' => $this->isHx($rq) && $page > 1, 'text' => self::STATUS_TEXT,
        ]);
    }

    public function show(Request $rq, Response $rs, array $args): Response
    {
        $it = $this->api()->get('items/' . rawurlencode($args['id']))['data']['item'] ?? [];
        $price = null;
        try {
            $rate = (array) ($this->api()->get('rates')['data'] ?? []);
            $price = $this->price($it, (float) (stripos((string) ($it['metalType'] ?? ''), 'silver') !== false ? ($rate['silver'] ?? 0) : ($rate['gold'] ?? 0)));
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'stock/show.twig', ['it' => $it, 'price' => $price, 'text' => self::STATUS_TEXT, 'active' => 'stock']);
    }

    // ── add / edit ────────────────────────────────────────────────────────────────────────────

    public function newForm(Request $rq, Response $rs): Response
    {
        return $this->form($rq, $rs, ['numberOfPieces' => 1, 'certificationType' => 'none'], null, null);
    }

    public function editForm(Request $rq, Response $rs, array $args): Response
    {
        $it = $this->api()->get('items/' . rawurlencode($args['id']))['data']['item'] ?? [];
        // the stored making charge = labour + making (from the rates) + a fixed part: show the fixed part, so saving keeps the total
        $p = $this->price($it, 0.0);
        $it['fixedMaking'] = max(0, round((float) ($it['makingCharge'] ?? 0) - (float) ($p['makingForBilling'] ?? 0), 2)) ?: '';
        return $this->form($rq, $rs, $it, null, $args['id']);
    }

    public function create(Request $rq, Response $rs): Response
    {
        return $this->save($rq, $rs, null);
    }

    public function update(Request $rq, Response $rs, array $args): Response
    {
        return $this->save($rq, $rs, $args['id']);
    }

    private function save(Request $rq, Response $rs, ?string $id): Response
    {
        $b = $this->input($rq);
        $body = $this->body($b, $id);
        try {
            $r = $id === null ? $this->api()->post('items', $body) : $this->api()->put('items/' . rawurlencode($id), $body);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->form($rq, $rs->withStatus(422), $b, $e->getMessage(), $id);
        }
        $item = $r['data']['item'] ?? $r['data'] ?? [];
        $this->flash('success', $id === null ? 'Stock saved: ' . ($item['barcode'] ?? '') : 'Stock updated');
        return $this->redirect($rs, '/stock/' . rawurlencode((string) ($item['_id'] ?? $id)));
    }

    /** Live price card while typing: worked out by the server with the shop's Stock Setting rules. */
    public function calc(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        $price = null;
        if ((float) ($b['netWeight'] ?? 0) > 0 || (float) ($b['grossWeight'] ?? 0) > 0) {
            try {
                $rate = (array) ($this->api()->get('rates')['data'] ?? []);
                $metal = strtolower((string) ($b['metalType'] ?? 'gold'));
                $price = $this->price($b, (float) (str_contains($metal, 'silver') ? ($rate['silver'] ?? 0) : ($rate['gold'] ?? 0)));
                $price['fixed'] = (float) ($b['fixedMaking'] ?? 0);
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        return $this->view($rq, $rs, 'stock/price.twig', ['price' => $price]);
    }

    // ── bulk stock: metal kept together without a barcode (dust, parts, sub-items, raw, in process) ──

    /** The panel on the Stock page: every active bulk entry and what it adds to the stock in the shop. */
    public function bulk(Request $rq, Response $rs): Response
    {
        $rows = [];
        try {
            $rows = (array) ($this->api()->get('stock/bulk-weights', ['isActive' => 'true'])['data']['bulkWeights'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        $totals = [];
        foreach ($rows as $r) {
            $m = strtolower((string) ($r['metalType'] ?? ''));
            $totals[$m] = ($totals[$m] ?? 0) + (float) ($r['weightGrams'] ?? 0);
        }
        return $this->view($rq, $rs, 'stock/bulk.twig', ['rows' => $rows, 'totals' => $totals, 'kinds' => self::KINDS]);
    }

    public function bulkNew(Request $rq, Response $rs): Response
    {
        return $this->bulkForm($rq, $rs, ['metalType' => 'gold', 'category' => 'dust'], null, null);
    }

    public function bulkEdit(Request $rq, Response $rs, array $args): Response
    {
        $rows = (array) ($this->api()->get('stock/bulk-weights', ['isActive' => 'true'])['data']['bulkWeights'] ?? []);
        foreach ($rows as $r) {
            if ((string) ($r['_id'] ?? '') === $args['id']) {
                return $this->bulkForm($rq, $rs, $r, null, $args['id']);
            }
        }
        return $this->toast($rs, 'error', 'That entry was not found');
    }

    public function bulkSave(Request $rq, Response $rs, array $args): Response
    {
        $id = $args['id'] ?? null;
        $b = $this->input($rq);
        $body = [
            'metalType' => (string) ($b['metalType'] ?? ''), 'weightGrams' => (string) ($b['weightGrams'] ?? ''), 'description' => trim((string) ($b['description'] ?? '')),
            'category' => (string) ($b['category'] ?? 'other'), 'purity' => trim((string) ($b['purity'] ?? '')), 'pieces' => trim((string) ($b['pieces'] ?? '')),
        ];
        try {
            if ($id === null) {
                $this->api()->post('stock/bulk-weights', $body);
            } else {
                unset($body['metalType']);   // the metal of an entry is not changed: remove it and add a new one
                $this->api()->put('stock/bulk-weights/' . rawurlencode($id), $body);
            }
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->bulkForm($rq, $rs->withStatus(422), $b, $e->getMessage(), $id);
        }
        return $this->done($rs, $id === null ? 'Bulk stock added' : 'Bulk stock updated');
    }

    public function bulkRemove(Request $rq, Response $rs, array $args): Response
    {
        try {
            $this->api()->delete('stock/bulk-weights/' . rawurlencode($args['id']));
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $this->trigger($rs, ['toast' => ['type' => 'success', 'text' => 'Bulk stock removed'], 'data-changed' => true]);
    }

    private function bulkForm(Request $rq, Response $rs, array $v, ?string $error, ?string $id): Response
    {
        return $this->view($rq, $rs, 'stock/bulk_form.twig', ['v' => $v, 'error' => $error, 'id' => $id, 'kinds' => self::KINDS, 'metals' => self::METALS]);
    }

    /** "Check the stock": what came in against what is in the shop, was sold and was wasted (the server works it out). */
    public function check(Request $rq, Response $rs): Response
    {
        $d = [];
        try {
            $d = (array) ($this->api()->get('stock/reconciliation')['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'stock/check.twig', ['d' => $d]);
    }

    // ── small actions ─────────────────────────────────────────────────────────────────────────

    public function setStatus(Request $rq, Response $rs, array $args): Response
    {
        $to = (string) ($this->input($rq)['to'] ?? '');
        $path = ['no_sell' => 'mark-no-sell', 'active' => 'mark-active', 'out' => 'remove-temporarily'][$to] ?? null;
        if ($path === null) {
            return $this->toast($rs, 'error', 'Unknown action');
        }
        try {
            $this->api()->put('items/' . rawurlencode($args['id']) . '/' . $path, []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $this->refreshWith($rs, 'success', 'Done');
    }

    public function remove(Request $rq, Response $rs, array $args): Response
    {
        try {
            $this->api()->delete('items/' . rawurlencode($args['id']));
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        $this->flash('success', 'Removed from stock');
        return $rs->withStatus(204)->withHeader('HX-Redirect', '/stock');
    }

    // ── helpers ───────────────────────────────────────────────────────────────────────────────

    /** The price of a piece by the server's rules (POST /stock-settings/calculate). */
    private function price(array $it, float $rate): array
    {
        $cert = (string) ($it['certificationType'] ?? 'none');
        return (array) ($this->api()->post('stock-settings/calculate', [
            'net' => $it['netWeight'] ?? '', 'gross' => $it['grossWeight'] ?? '', 'less' => $it['lessWeight'] ?? '', 'purity' => $it['purity'] ?? '',
            'wastage' => $it['wastage'] ?? '', 'custWastage' => $it['custWastage'] ?? '', 'labourRate' => $it['labourRate'] ?? '', 'makingRate' => $it['makingRate'] ?? '',
            'stoneValue' => $it['stoneValue'] ?? '', 'rate' => $rate, 'certification' => $cert, 'pieces' => $it['numberOfPieces'] ?? 1,
        ], 10)['data'] ?? []) + ['rate' => $rate];
    }

    /** Form values as the API wants them. Empty optional numbers are sent as empty so an old value can be cleared. */
    private function body(array $b, ?string $id): array
    {
        $out = [];
        foreach (['name', 'itemType', 'metalType', 'purity', 'description', 'stoneNote', 'supplier', 'size', 'certificationType'] as $k) {
            if (isset($b[$k])) {
                $out[$k] = trim((string) $b[$k]);
            }
        }
        foreach (['netWeight', 'grossWeight', 'lessWeight', 'stoneValue', 'wastage', 'custWastage', 'labourRate', 'makingRate', 'numberOfPieces', 'fixedMaking'] as $k) {
            if (isset($b[$k])) {
                $out[$k] = trim((string) $b[$k]);
            }
        }
        $out['huidNumber'] = ($out['certificationType'] ?? '') === 'huid' ? strtoupper(trim((string) ($b['huidNumber'] ?? ''))) : null;
        $out['autoMaking'] = true;
        if ($id === null) {
            $out['status'] = 'active';
        }
        return $out;
    }

    private function form(Request $rq, Response $rs, array $v, ?string $error, ?string $id): Response
    {
        $opts = (array) ($this->api()->get('settings/item')['data'] ?? []);
        return $this->view($rq, $rs, 'stock/form.twig', [
            'v' => $v, 'error' => $error, 'id' => $id, 'opts' => $opts, 'active' => 'stock',
            'certs' => ['none' => 'Not hallmarked', 'hallmarked' => 'Hallmarked', 'huid' => 'With HUID'],
        ]);
    }
}
