<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Admin Control > Branches & counters: open a branch, its bill letters and GSTIN, its billing counters, and who works where. */
final class AdminBranchController extends BaseController
{
    private function listAll(): array
    {
        try {
            return (array) ($this->api()->get('branches')['data']['branches'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return [];
        }
    }

    private function indexPage(Request $rq, Response $rs, array $more = []): Response
    {
        return $this->view($rq, $rs, 'admin/branches.twig', $more + ['branches' => $this->listAll(), 'error' => null, 'v' => [], 'active' => 'branches']);
    }

    public function index(Request $rq, Response $rs): Response
    {
        return $this->indexPage($rq, $rs);
    }

    private function fields(array $b): array
    {
        $out = [];
        foreach (['name', 'invoicePrefix', 'gstin', 'code', 'city', 'state', 'phone', 'address'] as $k) {
            $out[$k] = trim((string) ($b[$k] ?? ''));
        }
        return $out;
    }

    public function create(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        try {
            $r = $this->api()->post('branches', $this->fields($b));
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->indexPage($rq, $rs->withStatus(422), ['error' => $e->getMessage(), 'v' => $b]);
        }
        $this->flash('success', 'Branch opened. Now add its counters and put its staff there.');
        return $this->redirect($rs, '/admin/branches/' . rawurlencode((string) ($r['data']['id'] ?? 'main')));
    }

    private function showPage(Request $rq, Response $rs, string $id, array $more = []): Response
    {
        try {
            $br = (array) ($this->api()->get('branches/' . rawurlencode($id))['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->redirect($rs, '/admin/branches');
        }
        // people at other branches, so one can be moved here
        $others = [];
        try {
            foreach ((array) ($this->api()->get('users')['data']['users'] ?? []) as $u) {
                if (($u['isActive'] ?? true) !== false && ((string) ($u['branchId'] ?? 'main')) !== $id) {
                    $others[] = $u;
                }
            }
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'admin/branch.twig', $more + ['br' => $br, 'others' => $others, 'error' => null, 'cError' => null, 'v' => [], 'active' => 'branches']);
    }

    public function show(Request $rq, Response $rs, array $args): Response
    {
        return $this->showPage($rq, $rs, (string) $args['id']);
    }

    public function update(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        $body = $this->fields($b);
        $body['isActive'] = !empty($b['isActive']);
        try {
            $this->api()->patch('branches/' . rawurlencode((string) $args['id']), $body);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->showPage($rq, $rs->withStatus(422), (string) $args['id'], ['error' => $e->getMessage(), 'v' => $b]);
        }
        $this->flash('success', 'Saved.');
        return $this->redirect($rs, '/admin/branches/' . rawurlencode((string) $args['id']));
    }

    public function counterAdd(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->post('branches/' . rawurlencode((string) $args['id']) . '/counters', ['name' => trim((string) ($b['name'] ?? '')), 'code' => trim((string) ($b['code'] ?? '')), 'note' => trim((string) ($b['note'] ?? ''))]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->showPage($rq, $rs->withStatus(422), (string) $args['id'], ['cError' => $e->getMessage(), 'v' => $b]);
        }
        $this->flash('success', 'Counter added.');
        return $this->redirect($rs, '/admin/branches/' . rawurlencode((string) $args['id']));
    }

    public function counterSave(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->patch('branches/' . rawurlencode((string) $args['id']) . '/counters/' . rawurlencode((string) $args['cid']), [
                'name' => trim((string) ($b['name'] ?? '')), 'code' => trim((string) ($b['code'] ?? '')), 'note' => trim((string) ($b['note'] ?? '')), 'isActive' => !empty($b['isActive']),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->showPage($rq, $rs->withStatus(422), (string) $args['id'], ['cError' => $e->getMessage()]);
        }
        $this->flash('success', 'Counter saved.');
        return $this->redirect($rs, '/admin/branches/' . rawurlencode((string) $args['id']));
    }

    /** Put a person at this branch, at one of its counters (or none). */
    public function staffAssign(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        $uid = (string) ($args['uid'] ?? $b['uid'] ?? '');
        try {
            $this->api()->patch('branches/' . rawurlencode((string) $args['id']) . '/staff/' . rawurlencode($uid), ['counterId' => (string) ($b['counterId'] ?? '')]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->showPage($rq, $rs->withStatus(422), (string) $args['id'], ['error' => $e->getMessage()]);
        }
        $this->flash('success', 'Saved.');
        return $this->redirect($rs, '/admin/branches/' . rawurlencode((string) $args['id']));
    }
}
