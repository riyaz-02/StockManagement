<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/**
 * GST Summary: sales summary, invoice register, returns (GSTR-1 / GSTR-3B figures), input credit, due dates and the returns already filed.
 * Every figure is worked out by the API (services/gstReports.js); this only shows it and records what was filed.
 */
final class GstController extends BaseController
{
    private const TABS = ['summary' => 'Summary', 'register' => 'Sales register', 'returns' => 'Returns', 'itc' => 'Input credit', 'calendar' => 'Due dates', 'filings' => 'Filed returns'];
    private const RETURN_TYPES = ['GSTR-1', 'GSTR-3B', 'PMT-06', 'GSTR-9'];
    private const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

    public function index(Request $rq, Response $rs): Response
    {
        $tab = array_key_exists($this->q($rq, 'tab'), self::TABS) ? $this->q($rq, 'tab') : 'summary';
        $ctx = $this->context($rq, $tab);
        $data = [];
        try {
            $data = match ($tab) {
                'summary' => $this->summary($ctx),
                'register' => $this->register($rq, $ctx),
                'returns' => $this->returns($ctx),
                'itc' => $this->itc($ctx),
                'calendar' => $this->calendar($ctx),
                default => $this->filings($ctx),
            };
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $data = ['problem' => $e->getMessage()];
        }
        return $this->view($rq, $rs, 'gst/' . $tab . '.twig', $ctx + $data + ['active' => 'gst', 'tabs' => self::TABS, 'tab' => $tab]);
    }

    // ── one tab each ──────────────────────────────────────────────────────────────────────────

    private function summary(array $c): array
    {
        return ['s' => $this->api()->get('gst-reports/summary', $c['scope'] + $c['range'])['data'] ?? []];
    }

    private function register(Request $rq, array $c): array
    {
        $page = max(1, (int) $this->q($rq, 'page', '1'));
        $sort = $this->q($rq, 'sort', 'date');
        $dir = $this->q($rq, 'dir', 'desc') === 'asc' ? 'asc' : 'desc';
        $q = $this->q($rq, 'q');
        $r = $this->api()->get('gst-reports/register', array_filter($c['scope'] + $c['range'] + ['page' => $page, 'limit' => 50, 'sort' => $sort, 'dir' => $dir, 'q' => $q], fn ($v) => $v !== ''))['data'] ?? [];
        return ['reg' => $r, 'page' => $page, 'sort' => $sort, 'dir' => $dir, 'q' => $q, 'pages' => (int) ceil(((int) ($r['total'] ?? 0)) / 50)];
    }

    private function returns(array $c): array
    {
        $r = $this->api()->get('gst-reports/returns', ['gstin' => $c['gstin'], 'period' => $c['period']])['data'] ?? [];
        return ['r' => $r];
    }

    private function itc(array $c): array
    {
        return ['i' => $this->api()->get('gst-reports/itc', ['gstin' => $c['gstin'], 'period' => $c['period']])['data'] ?? []];
    }

    private function calendar(array $c): array
    {
        return ['cal' => $this->api()->get('gst-reports/calendar', ['gstin' => $c['gstin']])['data'] ?? []];
    }

    private function filings(array $c): array
    {
        return ['rows' => $this->api()->get('gst-reports/filings', ['gstin' => $c['gstin']])['data'] ?? [], 'types' => self::RETURN_TYPES];
    }

    // ── record a filing ───────────────────────────────────────────────────────────────────────

    public function filingForm(Request $rq, Response $rs): Response
    {
        $ctx = $this->context($rq, 'filings');
        return $this->view($rq, $rs, 'gst/filing_form.twig', ['gstin' => $ctx['gstin'], 'periods' => $ctx['periods'], 'types' => self::RETURN_TYPES, 'v' => ['filedOn' => date('Y-m-d'), 'returnType' => 'GSTR-3B', 'period' => $ctx['period']], 'error' => null]);
    }

    public function filingSave(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        $gstin = (string) ($b['gstin'] ?? '');
        try {
            $this->api()->post('gst-reports/filings?gstin=' . rawurlencode($gstin), [
                'returnType' => (string) ($b['returnType'] ?? ''), 'period' => (string) ($b['period'] ?? ''), 'filedOn' => (string) ($b['filedOn'] ?? ''), 'arn' => (string) ($b['arn'] ?? ''),
                'taxLiability' => (string) ($b['taxLiability'] ?? ''), 'itcUsed' => (string) ($b['itcUsed'] ?? ''), 'cashPaid' => (string) ($b['cashPaid'] ?? ''),
                'lateFee' => (string) ($b['lateFee'] ?? ''), 'interest' => (string) ($b['interest'] ?? ''), 'nil' => !empty($b['nil']), 'note' => (string) ($b['note'] ?? ''),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $ctx = $this->context($rq, 'filings');
            return $this->view($rq, $rs->withStatus(422), 'gst/filing_form.twig', ['gstin' => $gstin, 'periods' => $ctx['periods'], 'types' => self::RETURN_TYPES, 'v' => $b, 'error' => $e->getMessage()]);
        }
        return $this->refreshWith($rs, 'success', 'Filing recorded');
    }

    /** The CSV the accountant asks for (register / HSN / B2CS / B2CL / metal summary). */
    public function export(Request $rq, Response $rs): Response
    {
        $c = $this->context($rq, 'summary');
        $type = in_array($this->q($rq, 'type'), ['register', 'hsn', 'b2cs', 'b2cl', 'metal'], true) ? $this->q($rq, 'type') : 'register';
        $d = $this->api()->get('gst-reports/export', $c['scope'] + $c['range'] + ['type' => $type])['data'] ?? [];
        $rs->getBody()->write("\xEF\xBB\xBF" . (string) ($d['csv'] ?? ''));
        $name = preg_replace('/[^A-Za-z0-9._-]/', '_', (string) ($d['filename'] ?? 'gst.csv'));
        return $rs->withHeader('Content-Type', 'text/csv; charset=utf-8')->withHeader('Content-Disposition', 'attachment; filename="' . $name . '"');
    }

    // ── shared: which GSTIN, which dates, which period ───────────────────────────────────────

    private function context(Request $rq, string $tab): array
    {
        $set = [];
        try {
            $set = $this->api()->get('gst-reports/settings')['data'] ?? [];
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        $regs = (array) ($set['registrations'] ?? []);
        $default = '';
        foreach ($regs as $r) {
            if (!empty($r['isDefault'])) {
                $default = (string) $r['gstin'];
            }
        }
        $default = $default ?: (string) ($regs[0]['gstin'] ?? '');
        $asked = $this->q($rq, 'gstin');
        $known = array_column($regs, 'gstin');
        $all = $asked === 'ALL' && in_array($tab, ['summary', 'register'], true) && count($regs) > 1;
        $gstin = $all ? 'ALL' : (in_array($asked, $known, true) ? $asked : $default);
        $freq = (string) ($set['settings']['frequency'] ?? 'monthly');
        $periods = $this->periods($freq);
        $period = $this->q($rq, 'period');
        if (!isset($periods[$period])) {
            $period = (string) array_key_first($periods);
        }
        return [
            'gstin' => $gstin, 'regs' => $regs, 'multi' => count($regs) > 1, 'freq' => $freq, 'periods' => $periods, 'period' => $period,
            'scope' => ['gstin' => $gstin], 'range' => $this->dates($rq), 'settings' => $set['settings'] ?? [], 'today' => (string) ($set['today'] ?? date('Y-m-d')),
        ];
    }

    /** from / to for the summary and register: This month, Last month, This quarter, This financial year, or typed dates. */
    private function dates(Request $rq): array
    {
        $today = date('Y-m-d');
        $quick = $this->q($rq, 'quick', 'month');
        $from = $this->q($rq, 'from');
        $to = $this->q($rq, 'to');
        $ok = fn (string $d) => preg_match('/^\d{4}-\d{2}-\d{2}$/', $d) === 1;
        $y = (int) date('Y');
        $m = (int) date('n');
        if ($ok($from) && $ok($to)) {
            $quick = 'custom';
        } elseif ($quick === 'last') {
            $from = date('Y-m-01', strtotime('first day of last month'));
            $to = date('Y-m-t', strtotime('first day of last month'));
        } elseif ($quick === 'quarter') {
            $idx = intdiv(($m - 4 + 12) % 12, 3);        // 0..3: which quarter of the financial year (April to March)
            $startMonth = ((3 + 3 * $idx) % 12) + 1;
            $startYear = $startMonth > $m ? $y - 1 : $y;
            $from = sprintf('%04d-%02d-01', $startYear, $startMonth);
            $to = $today;
        } elseif ($quick === 'year') {
            $from = ($m >= 4 ? $y : $y - 1) . '-04-01';
            $to = $today;
        } else {
            $quick = 'month';
            $from = date('Y-m-01');
            $to = $today;
        }
        return ['from' => $from, 'to' => $to, 'quick' => $quick];
    }

    /** Return periods to pick from, newest first: months, or FY quarters when the shop files quarterly. @return array<string,string> */
    private function periods(string $freq): array
    {
        $out = [];
        if ($freq === 'quarterly') {
            $y = (int) date('Y');
            $m = (int) date('n');
            $fy = $m >= 4 ? $y : $y - 1;
            $q = intdiv(($m - 4 + 12) % 12, 3) + 1;
            for ($i = 0; $i < 10; $i++) {
                $start = ($q - 1) * 3 + 4;
                $names = [];
                foreach ([0, 1, 2] as $k) {
                    $names[] = substr(self::MONTHS[($start + $k - 1) % 12], 0, 3);
                }
                $out["$fy-Q$q"] = "Q$q FY " . substr((string) $fy, 2) . '-' . substr((string) ($fy + 1), 2) . ' (' . $names[0] . '–' . $names[2] . ')';
                if (--$q < 1) {
                    $q = 4;
                    $fy--;
                }
            }
            return $out;
        }
        for ($i = 0; $i < 24; $i++) {
            $t = strtotime("first day of -$i month");
            $out[date('Y-m', $t)] = self::MONTHS[(int) date('n', $t) - 1] . ' ' . date('Y', $t);
        }
        return $out;
    }
}
