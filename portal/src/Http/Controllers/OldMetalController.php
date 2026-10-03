<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Old metal taken from customers (URD) and raw metal bought, valued by the shop's rules on the server. */
final class OldMetalController extends BaseController
{
    private const PURITIES = ['24K', '22K', '18K', '14K', '999', '925', '800'];

    public function index(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'oldmetal/index.twig', ['active' => 'oldmetal']);
    }

    public function list(Request $rq, Response $rs): Response
    {
        $kind = $this->q($rq, 'kind');
        $used = $this->q($rq, 'used');
        $q = $this->q($rq, 'q');
        $r = $this->api()->get('old-metal', array_filter(['kind' => $kind, 'used' => $used, 'q' => $q], fn ($v) => $v !== ''));
        return $this->view($rq, $rs, 'oldmetal/list.twig', ['rows' => $r['data']['rows'] ?? [], 'totals' => $r['data']['totals'] ?? [], 'kind' => $kind, 'used' => $used, 'q' => $q]);
    }

    public function form(Request $rq, Response $rs): Response
    {
        $kind = $this->q($rq, 'kind', 'old') === 'raw' ? 'raw' : 'old';
        $rate = (array) ($this->api()->get('rates')['data'] ?? []);
        $v = ['kind' => $kind, 'metalType' => 'gold', 'purity' => '22K', 'rate' => ($rate['gold'] ?? 0) > 0 ? $rate['gold'] : ''];
        return $this->view($rq, $rs, 'oldmetal/form.twig', ['v' => $v, 'error' => null, 'purities' => self::PURITIES, 'calc' => null, 'rid' => $this->requestId('om')]);
    }

    /** Live valuation while typing: the SERVER works it out (same rules as the app and the bill). */
    public function calc(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        $calc = null;
        if ((float) ($b['net'] ?? 0) > 0 || (float) ($b['gross'] ?? 0) > 0) {
            try {
                $calc = $this->api()->post('old-metal/calculate', $this->payload($b), 10)['data'] ?? null;
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        return $this->view($rq, $rs, 'oldmetal/calc.twig', ['calc' => $calc, 'v' => $b]);
    }

    public function create(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->post('old-metal', $this->payload($b) + [
                'customerId' => (string) ($b['customerId'] ?? ''), 'customerName' => (string) ($b['customerName'] ?? ''), 'customerMobile' => (string) ($b['customerMobile'] ?? ''), 'note' => (string) ($b['note'] ?? ''),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->view($rq, $rs->withStatus(422), 'oldmetal/form.twig', ['v' => $b, 'error' => $e->getMessage(), 'purities' => self::PURITIES, 'calc' => null, 'rid' => (string) ($b['rid'] ?? '')]);
        }
        return $this->done($rs, ($b['kind'] ?? '') === 'raw' ? 'Raw metal purchase saved' : 'Old metal saved');
    }

    public function cancel(Request $rq, Response $rs, array $args): Response
    {
        try {
            $this->api()->post('old-metal/' . rawurlencode($args['id']) . '/cancel', []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $this->trigger($rs, ['toast' => ['type' => 'success', 'text' => 'Entry cancelled'], 'data-changed' => true]);
    }

    private function payload(array $b): array
    {
        return [
            'kind' => ($b['kind'] ?? 'old') === 'raw' ? 'raw' : 'old', 'metalType' => (string) ($b['metalType'] ?? 'gold'), 'purity' => (string) ($b['purity'] ?? ''),
            'gross' => (string) ($b['gross'] ?? ''), 'less' => (string) ($b['less'] ?? ''), 'net' => (string) ($b['net'] ?? ''),
            'deduction' => (string) ($b['deduction'] ?? ''), 'rate' => (string) ($b['rate'] ?? ''),
        ];
    }
}
