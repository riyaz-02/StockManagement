<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** The shop's running costs: pick a period, see what was spent, add one in a pop-up. */
final class ExpenseController extends BaseController
{
    private const CATEGORIES = ['Salary', 'Rent', 'Electricity', 'Tea / food', 'Transport', 'Repair / labour', 'Packing / tags', 'Advertising', 'Other'];
    private const MODES = ['Cash', 'Online', 'Card', 'Cheque'];

    public function index(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'expenses/index.twig', ['active' => 'expenses', 'range' => $this->range($rq)]);
    }

    public function list(Request $rq, Response $rs): Response
    {
        $range = $this->range($rq);
        $d = $this->api()->get('expenses', ['from' => $range['from'], 'to' => $range['to']])['data'] ?? [];
        $cat = $this->q($rq, 'category');
        $rows = array_values(array_filter((array) ($d['rows'] ?? []), fn ($r) => $cat === '' || ($r['category'] ?? '') === $cat));
        $total = array_sum(array_map(fn ($r) => (float) $r['amount'], $rows));
        return $this->view($rq, $rs, 'expenses/list.twig', ['rows' => $rows, 'total' => $total, 'range' => $range, 'category' => $cat]);
    }

    public function form(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'expenses/form.twig', ['categories' => self::CATEGORIES, 'modes' => self::MODES, 'v' => ['category' => 'Tea / food', 'mode' => 'Cash', 'date' => date('Y-m-d')], 'error' => null]);
    }

    public function create(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->post('expenses', [
                'amount' => (string) ($b['amount'] ?? ''), 'category' => (string) ($b['category'] ?? 'Other'), 'mode' => (string) ($b['mode'] ?? 'Cash'),
                'note' => (string) ($b['note'] ?? ''), 'date' => (string) ($b['date'] ?? ''),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->view($rq, $rs->withStatus(422), 'expenses/form.twig', ['categories' => self::CATEGORIES, 'modes' => self::MODES, 'v' => $b, 'error' => $e->getMessage()]);
        }
        return $this->done($rs, 'Expense saved');
    }

    public function cancel(Request $rq, Response $rs, array $args): Response
    {
        try {
            $this->api()->delete('expenses/' . rawurlencode($args['id']));
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $this->trigger($rs, ['toast' => ['type' => 'success', 'text' => 'Expense cancelled'], 'data-changed' => true]);
    }
}
