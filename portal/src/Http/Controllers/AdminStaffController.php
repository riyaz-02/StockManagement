<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Portal\Auth\Session;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Admin Control: who can sign in (staff), what each role may do, and what one person may do on top of their role. */
final class AdminStaffController extends BaseController
{
    private const ROLES = ['manager' => 'Manager', 'staff' => 'Staff', 'viewer' => 'Viewer (look only)'];
    private const ALL_ROLES = ['admin' => 'Admin', 'owner' => 'Owner', 'manager' => 'Manager', 'staff' => 'Staff', 'viewer' => 'Viewer (look only)'];

    public function index(Request $rq, Response $rs): Response
    {
        $tab = $this->q($rq, 'tab') === 'roles' ? 'roles' : 'people';
        $data = ['tab' => $tab, 'active' => 'staff', 'roles' => self::ROLES];
        if ($tab === 'people') {
            $users = (array) ($this->api()->get('users')['data']['users'] ?? []);
            $data['users'] = $users;
            $data['names'] = self::ALL_ROLES;
        } else {
            $role = array_key_exists($this->q($rq, 'role'), self::ROLES) ? $this->q($rq, 'role') : 'staff';
            $defs = (array) ($this->api()->get('permissions/definitions')['data']['groups'] ?? []);
            $grids = (array) ($this->api()->get('permissions/roles')['data']['grids'] ?? []);
            $data += ['role' => $role, 'groups' => $defs, 'grid' => (array) ($grids[$role] ?? [])];
        }
        return $this->view($rq, $rs, 'admin/staff.twig', $data);
    }

    /** Who has the app or the website open right now, and roughly where in it (polled every 15s). */
    public function live(Request $rq, Response $rs): Response
    {
        $rows = [];
        try {
            $rows = (array) ($this->api()->get('presence')['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'admin/staff_live.twig', ['rows' => $rows]);
    }

    // ── a person ──────────────────────────────────────────────────────────────────────────────

    public function newForm(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'admin/staff_new.twig', ['v' => ['role' => 'staff'], 'error' => null, 'roles' => self::ALL_ROLES, 'branches' => $this->branches()]);
    }

    public function create(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->post('users', [
                'name' => trim((string) ($b['name'] ?? '')), 'mobile' => preg_replace('/\D/', '', (string) ($b['mobile'] ?? '')), 'password' => (string) ($b['password'] ?? ''),
                'role' => (string) ($b['role'] ?? 'staff'), 'branchId' => (string) ($b['branchId'] ?? ''), 'counterId' => (string) ($b['counterId'] ?? ''),
                'username' => trim((string) ($b['username'] ?? '')), 'email' => trim((string) ($b['email'] ?? '')),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->view($rq, $rs->withStatus(422), 'admin/staff_new.twig', ['v' => $b, 'error' => $e->getMessage(), 'roles' => self::ALL_ROLES, 'branches' => $this->branches()]);
        }
        return $this->refreshWith($rs, 'success', 'Staff added');
    }

    public function show(Request $rq, Response $rs, array $args): Response
    {
        $id = rawurlencode($args['id']);
        $u = (array) ($this->api()->get("users/$id")['data']['user'] ?? []);
        $defs = (array) ($this->api()->get('permissions/definitions')['data']['groups'] ?? []);
        $grids = (array) ($this->api()->get('permissions/roles')['data']['grids'] ?? []);
        $full = in_array($u['role'] ?? '', ['admin', 'owner'], true);
        return $this->view($rq, $rs, 'admin/person.twig', [
            'u' => $u + ['permissionOverrides' => []], 'groups' => $defs, 'grid' => (array) ($grids[$u['role'] ?? ''] ?? []), 'full' => $full,
            'roles' => self::ALL_ROLES, 'branches' => $this->branches(), 'self' => (string) (Session::user()['id'] ?? '') === (string) ($u['_id'] ?? ''), 'active' => 'staff',
        ]);
    }

    public function update(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->put('users/' . rawurlencode($args['id']), [
                'name' => trim((string) ($b['name'] ?? '')), 'mobile' => preg_replace('/\D/', '', (string) ($b['mobile'] ?? '')),
                'role' => (string) ($b['role'] ?? ''), 'branchId' => (string) ($b['branchId'] ?? ''), 'counterId' => (string) ($b['counterId'] ?? ''), 'isActive' => !empty($b['isActive']),
                'username' => trim((string) ($b['username'] ?? '')), 'email' => trim((string) ($b['email'] ?? '')),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $this->flash('error', $e->getMessage());
            return $this->redirect($rs, '/admin/staff/' . rawurlencode($args['id']));
        }
        $this->flash('success', 'Saved');
        return $this->redirect($rs, '/admin/staff/' . rawurlencode($args['id']));
    }

    public function passwordForm(Request $rq, Response $rs, array $args): Response
    {
        $u = (array) ($this->api()->get('users/' . rawurlencode($args['id']))['data']['user'] ?? []);
        return $this->view($rq, $rs, 'admin/password.twig', ['u' => $u, 'error' => null]);
    }

    public function password(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        $pw = (string) ($b['password'] ?? '');
        $u = (array) ($this->api()->get('users/' . rawurlencode($args['id']))['data']['user'] ?? []);
        if ($pw !== (string) ($b['again'] ?? '')) {
            return $this->view($rq, $rs->withStatus(422), 'admin/password.twig', ['u' => $u, 'error' => 'The two passwords are not the same.']);
        }
        try {
            $this->api()->put('users/' . rawurlencode($args['id']) . '/reset-password', ['newPassword' => $pw]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->view($rq, $rs->withStatus(422), 'admin/password.twig', ['u' => $u, 'error' => $e->getMessage()]);
        }
        return $this->done($rs, 'Password changed. Tell them the new one.');
    }

    /** Per-person permissions: each key is "as the role", "allowed" or "blocked". */
    public function permissions(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        $over = [];
        foreach ((array) ($b['perm'] ?? []) as $key => $val) {
            $over[(string) $key] = $val === 'allow' ? true : ($val === 'block' ? false : null);
        }
        try {
            $this->api()->put('users/' . rawurlencode($args['id']) . '/permission-overrides', ['overrides' => $over]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->refreshWith($rs, 'error', $e->getMessage());
        }
        return $this->refreshWith($rs, 'success', 'Permissions saved. They apply at once, even on the phone.');
    }

    public function deactivate(Request $rq, Response $rs, array $args): Response
    {
        try {
            $this->api()->delete('users/' . rawurlencode($args['id']));
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $this->refreshWith($rs, 'success', 'Login switched off');
    }

    // ── a role ────────────────────────────────────────────────────────────────────────────────

    public function saveRole(Request $rq, Response $rs, array $args): Response
    {
        $role = $args['role'];
        if (!array_key_exists($role, self::ROLES)) {
            return $this->toast($rs, 'error', 'Unknown role');
        }
        $keys = array_map('strval', (array) ($this->input($rq)['allkeys'] ?? []));
        $on = array_map('strval', (array) ($this->input($rq)['perm'] ?? []));
        $perms = [];
        foreach ($keys as $k) {
            $perms[$k] = in_array($k, $on, true);
        }
        try {
            $this->api()->put('permissions/roles/' . rawurlencode($role), ['permissions' => $perms]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->refreshWith($rs, 'error', $e->getMessage());
        }
        return $this->refreshWith($rs, 'success', 'Role saved. Everyone in this role gets it at once.');
    }

    /** @return array<int,array{_id:string,name:string}> */
    private function branches(): array
    {
        try {
            // each branch with its live counters (for the Counter drop-down next to the Branch one)
            $rows = (array) ($this->api()->get('branches')['data']['branches'] ?? []);
            return array_values(array_map(fn ($b) => ['_id' => $b['id'], 'name' => $b['name'], 'counters' => array_values(array_filter((array) ($b['counters'] ?? []), fn ($c) => ($c['isActive'] ?? true) !== false))], array_filter($rows, fn ($b) => ($b['isActive'] ?? true) !== false)));
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return [];
        }
    }
}
