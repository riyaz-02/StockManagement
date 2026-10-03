<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/**
 * Stock Summary: what came into the business against what is in the shop, was sold and was wasted, and the difference.
 * Every number is worked out by the server (the same answer the phone app shows); this only draws it.
 */
final class StockSummaryController extends BaseController
{
    public function index(Request $rq, Response $rs): Response
    {
        $d = [];
        try {
            $d = (array) ($this->api()->get('stock/summary')['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'stock/summary.twig', ['d' => $d, 'active' => 'summary']);
    }

    /** Today's snapshot: the server builds it (nothing from the browser is trusted). */
    public function snapshot(Request $rq, Response $rs): Response
    {
        try {
            $r = $this->api()->post('stock/summary/snapshot', []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $this->refreshWith($rs, 'success', (string) ($r['message'] ?? 'Snapshot saved'));
    }

    /** "Show more" in the recent movements. */
    public function movements(Request $rq, Response $rs): Response
    {
        $limit = max(1, min(60, (int) $this->q($rq, 'limit', '30')));
        $rows = [];
        try {
            $rows = (array) ($this->api()->get('stock/summary/movements', ['limit' => $limit])['data']['movements'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'stock/movements.twig', ['rows' => $rows, 'all' => $limit > 8]);
    }

    // ── history ───────────────────────────────────────────────────────────────────────────────

    public function history(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'stock/history.twig', $this->historyData($rq) + ['active' => 'summary']);
    }

    /** The history as a spreadsheet file (built here from the same answer the page uses). */
    public function historyCsv(Request $rq, Response $rs): Response
    {
        $h = $this->historyData($rq);
        $q = static fn ($v): string => preg_match('/[",\n]/', (string) $v) ? '"' . str_replace('"', '""', (string) $v) . '"' : (string) $v;
        $lines = [implode(',', ['Period', 'Date', 'Metal', 'Stock g', 'In g', 'Out g', 'Difference g', 'Difference %', 'Level'])];
        foreach ($h['rows'] as $r) {
            foreach (['gold', 'silver'] as $m) {
                $x = $r[$m];
                $lines[] = implode(',', array_map($q, [$r['label'], $r['date'], $m, $x['stock'], $x['in'] ?? '', $x['out'] ?? '', $x['variance'], $x['variancePct'], $x['severity'] ?? '']));
            }
        }
        $rs->getBody()->write(implode("\n", $lines) . "\n");
        return $rs->withHeader('Content-Type', 'text/csv; charset=utf-8')->withHeader('Content-Disposition', 'attachment; filename="stock-history.csv"');
    }

    /** @return array<string,mixed> */
    private function historyData(Request $rq): array
    {
        $view = in_array($this->q($rq, 'view', 'daily'), ['daily', 'weekly', 'monthly'], true) ? $this->q($rq, 'view', 'daily') : 'daily';
        $metal = in_array($this->q($rq, 'metal'), ['gold', 'silver'], true) ? $this->q($rq, 'metal') : '';
        $quick = $this->q($rq, 'quick', 'all');
        $from = $this->q($rq, 'from');
        $to = $this->q($rq, 'to');
        $ymd = '/^\d{4}-\d{2}-\d{2}$/';
        if (in_array($quick, ['30', '90', '365'], true)) {
            $from = date('Y-m-d', strtotime('-' . $quick . ' days'));
            $to = date('Y-m-d');
        } elseif ($quick !== 'custom') {
            $from = '';
            $to = '';
        }
        $params = ['view' => $view];
        if (preg_match($ymd, $from)) {
            $params['from'] = $from;
        }
        if (preg_match($ymd, $to)) {
            $params['to'] = $to;
        }
        $h = [];
        try {
            $h = (array) ($this->api()->get('stock/summary/history', $params)['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        $rows = (array) ($h['rows'] ?? []);
        $asc = array_reverse($rows);
        $mixed = count(array_unique(array_map(fn ($r) => $r['basis'] ?? 'ledger', $rows))) > 1;
        $changeDate = '';
        foreach ($asc as $r) {
            if (!empty($r['methodChange'])) {
                $changeDate = (string) $r['date'];
                break;
            }
        }
        return [
            'rows' => $rows, 'trend' => (array) ($h['trend'] ?? []), 'bounds' => $h['bounds'] ?? null, 'view' => $view, 'metal' => $metal, 'quick' => $quick,
            'from' => $params['from'] ?? '', 'to' => $params['to'] ?? '', 'mixed' => $mixed, 'changeDate' => $changeDate,
            'charts' => [
                'gold_stock' => $this->spark($asc, 'gold', 'stock'), 'silver_stock' => $this->spark($asc, 'silver', 'stock'),
                'gold_diff' => $this->spark($asc, 'gold', 'variance'), 'silver_diff' => $this->spark($asc, 'silver', 'variance'),
            ],
        ];
    }

    /** A small line chart as SVG path data (oldest to newest) for one number of one metal. */
    private function spark(array $asc, string $metal, string $field): array
    {
        $vals = [];
        foreach ($asc as $r) {
            $vals[] = ['d' => (string) ($r['date'] ?? ''), 'v' => (float) ($r[$metal][$field] ?? 0)];
        }
        if (count($vals) < 2) {
            return ['ok' => false];
        }
        $w = 600.0;
        $h = 150.0;
        $pad = 10.0;
        $min = min(array_column($vals, 'v'));
        $max = max(array_column($vals, 'v'));
        if ($field === 'variance') {
            $min = min($min, 0.0);
            $max = max($max, 0.0);
        }
        if ($max - $min < 1e-9) {
            $max += 1;
            $min -= 1;
        }
        $n = count($vals);
        $pts = [];
        $path = '';
        foreach ($vals as $i => $p) {
            $x = $pad + ($w - 2 * $pad) * ($n > 1 ? $i / ($n - 1) : 0);
            $y = $pad + ($h - 2 * $pad) * (1 - ($p['v'] - $min) / ($max - $min));
            $path .= ($i === 0 ? 'M' : 'L') . round($x, 1) . ',' . round($y, 1) . ' ';
            $pts[] = ['x' => round($x, 1), 'y' => round($y, 1), 'd' => $p['d'], 'v' => round($p['v'], 3)];
        }
        $zero = $field === 'variance' ? round($pad + ($h - 2 * $pad) * (1 - (0 - $min) / ($max - $min)), 1) : null;
        return ['ok' => true, 'path' => trim($path), 'min' => round($min, 3), 'max' => round($max, 3), 'zero' => $zero, 'first' => $vals[0]['d'], 'last' => $vals[$n - 1]['d'], 'last_v' => round($vals[$n - 1]['v'], 3), 'points' => $n <= 60 ? $pts : []];
    }
}
