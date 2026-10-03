<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/**
 * Metal wastage reports: report, look, approve, reject. The rules (a report counts only when approved, nobody approves their own,
 * an approved one is final) are the server's; this draws the forms and shows its answer.
 */
final class WastageController extends BaseController
{
    private const METALS = ['gold' => 'Gold', 'silver' => 'Silver'];
    private const CATEGORIES = ['Manufacturing', 'Polishing', 'Stone Setting', 'Other'];

    /** The panel on the Summary: the latest reports and what waits for approval. */
    public function panel(Request $rq, Response $rs): Response
    {
        $d = [];
        try {
            $d = (array) ($this->api()->get('stock/wastage', ['limit' => 6])['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'wastage/panel.twig', ['d' => $d]);
    }

    public function index(Request $rq, Response $rs): Response
    {
        $page = max(1, (int) $this->q($rq, 'page', '1'));
        $status = $this->q($rq, 'status');
        $metal = $this->q($rq, 'metal');
        $cat = $this->q($rq, 'category');
        $d = [];
        try {
            $d = (array) ($this->api()->get('stock/wastage', array_filter(['status' => $status, 'metal' => $metal, 'category' => $cat, 'q' => $this->q($rq, 'q'), 'page' => $page, 'limit' => 20], fn ($v) => $v !== ''))['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'wastage/index.twig', ['d' => $d, 'status' => $status, 'metal' => $metal, 'category' => $cat, 'q' => $this->q($rq, 'q'), 'page' => $page, 'categories' => self::CATEGORIES, 'active' => 'summary']);
    }

    public function newForm(Request $rq, Response $rs): Response
    {
        return $this->form($rq, $rs, ['date' => date('Y-m-d'), 'metal' => 'gold', 'category' => 'Manufacturing'], null, null);
    }

    public function editForm(Request $rq, Response $rs, array $args): Response
    {
        $r = (array) ($this->api()->get('stock/wastage/' . rawurlencode($args['id']))['data']['report'] ?? []);
        return $this->form($rq, $rs, $r, null, $args['id']);
    }

    public function save(Request $rq, Response $rs, array $args): Response
    {
        $id = $args['id'] ?? null;
        $b = $this->input($rq);
        $body = [
            'date' => (string) ($b['date'] ?? ''), 'metal' => (string) ($b['metal'] ?? ''), 'amount' => (string) ($b['amount'] ?? ''),
            'category' => (string) ($b['category'] ?? ''), 'reason' => trim((string) ($b['reason'] ?? '')), 'remarks' => trim((string) ($b['remarks'] ?? '')),
        ];
        try {
            if ($id === null) {
                $this->api()->post('stock/wastage', $body);
            } else {
                $this->api()->put('stock/wastage/' . rawurlencode($id), $body);
            }
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->form($rq, $rs->withStatus(422), $b, $e->getMessage(), $id);
        }
        return $this->done($rs, $id === null ? 'Wastage reported: it counts once someone approves it' : 'Wastage report updated');
    }

    public function show(Request $rq, Response $rs, array $args): Response
    {
        $r = (array) ($this->api()->get('stock/wastage/' . rawurlencode($args['id']))['data']['report'] ?? []);
        return $this->view($rq, $rs, 'wastage/show.twig', ['r' => $r, 'me' => (string) (\Portal\Auth\Session::user()['id'] ?? '')]);
    }

    public function approve(Request $rq, Response $rs, array $args): Response
    {
        try {
            $this->api()->post('stock/wastage/' . rawurlencode($args['id']) . '/approve', ['comment' => trim((string) ($this->input($rq)['comment'] ?? ''))]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $this->done($rs, 'Approved: it now counts in the metal balance');
    }

    public function rejectForm(Request $rq, Response $rs, array $args): Response
    {
        $r = (array) ($this->api()->get('stock/wastage/' . rawurlencode($args['id']))['data']['report'] ?? []);
        return $this->view($rq, $rs, 'wastage/reject.twig', ['r' => $r, 'error' => null]);
    }

    public function reject(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->post('stock/wastage/' . rawurlencode($args['id']) . '/reject', ['comment' => trim((string) ($b['comment'] ?? ''))]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $r = (array) ($this->api()->get('stock/wastage/' . rawurlencode($args['id']))['data']['report'] ?? []);
            return $this->view($rq, $rs->withStatus(422), 'wastage/reject.twig', ['r' => $r, 'error' => $e->getMessage()]);
        }
        return $this->done($rs, 'Rejected: it does not count');
    }

    private function form(Request $rq, Response $rs, array $v, ?string $error, ?string $id): Response
    {
        return $this->view($rq, $rs, 'wastage/form.twig', ['v' => $v, 'error' => $error, 'id' => $id, 'metals' => self::METALS, 'categories' => self::CATEGORIES]);
    }
}
