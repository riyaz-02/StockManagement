<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Customers, suppliers and karigars. Customers can be added and edited (a partial edit never clears what is not on the form). */
final class DirectoryController extends BaseController
{
    private const PAGE = 25;
    private const TABS = ['customers' => 'Customers', 'suppliers' => 'Suppliers', 'karigars' => 'Karigars'];

    public function index(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'directory/index.twig', ['active' => 'directory']);
    }

    public function list(Request $rq, Response $rs): Response
    {
        $tab = array_key_exists($this->q($rq, 'tab'), self::TABS) ? $this->q($rq, 'tab') : 'customers';
        $q = $this->q($rq, 'q');
        $page = max(1, (int) $this->q($rq, 'page', '1'));
        $r = $this->api()->get('directory/' . $tab, array_filter(['q' => $q, 'page' => $page, 'limit' => self::PAGE], fn ($v) => $v !== ''));
        return $this->view($rq, $rs, 'directory/list.twig', [
            'tab' => $tab, 'tabs' => self::TABS, 'q' => $q, 'page' => $page, 'rows' => $r['data'] ?? [], 'pg' => $r['pagination'] ?? [], 'more' => $this->isHx($rq) && $page > 1,
        ]);
    }

    public function show(Request $rq, Response $rs, array $args): Response
    {
        $id = rawurlencode($args['id']);
        $c = $this->api()->get("directory/customers/$id")['data'] ?? [];
        $sum = [];
        try {
            $sum = (array) ($this->api()->get("billing/customer/$id")['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        $c += ['customer_name' => '', 'customer_name_bengali' => '', 'whatsapp_no' => '', 'mobile_no' => '', 'email' => '', 'address' => ''];
        $p = ((array) ($c['profile'] ?? [])) + ['customerCode' => '', 'membershipStatus' => 'Regular', 'contacts' => [], 'city' => '', 'state' => '', 'pincode' => '', 'gstNo' => '', 'panNo' => '', 'notes' => ''];
        return $this->view($rq, $rs, 'directory/show.twig', ['c' => $c, 'p' => $p, 'sum' => $sum, 'active' => 'directory']);
    }

    public function party(Request $rq, Response $rs, array $args): Response
    {
        $kind = $args['kind'] === 'karigars' ? 'karigars' : 'suppliers';
        $x = $this->api()->get("directory/$kind/" . rawurlencode($args['id']))['data'] ?? [];
        $x += ['firmName' => '', 'firstName' => '', 'lastName' => '', 'mobile' => '', 'phone' => '', 'email' => '', 'address' => '', 'city' => '', 'state' => '', 'pincode' => '', 'gstNo' => '', 'panNo' => '', 'bank' => []];
        return $this->view($rq, $rs, 'directory/party.twig', ['x' => $x, 'kind' => $kind, 'active' => 'directory']);
    }

    // ── add / edit a customer ─────────────────────────────────────────────────────────────────

    public function newForm(Request $rq, Response $rs): Response
    {
        return $this->form($rq, $rs, [], null, null);
    }

    public function editForm(Request $rq, Response $rs, array $args): Response
    {
        $c = $this->api()->get('directory/customers/' . rawurlencode($args['id']))['data'] ?? [];
        $p = $c['profile'] ?? [];
        $contacts = (array) ($p['contacts'] ?? []);
        $v = [
            'name' => $c['customer_name'] ?? '', 'nameBengali' => $c['customer_name_bengali'] ?? '', 'address' => $c['address'] ?? '',
            'phone1' => $contacts[0]['number'] ?? ($c['whatsapp_no'] ?? ''), 'phone2' => $contacts[1]['number'] ?? ($c['mobile_no'] ?? ''),
            'city' => $p['city'] ?? '', 'state' => $p['state'] ?? '', 'pincode' => $p['pincode'] ?? '', 'gstNo' => $p['gstNo'] ?? '', 'panNo' => $p['panNo'] ?? '',
            'notes' => $p['notes'] ?? '', 'email' => $c['email'] ?? '', 'membershipStatus' => $p['membershipStatus'] ?? 'Regular',
            'expectedUpdatedAt' => $c['updated_at'] ?? '',
        ];
        return $this->form($rq, $rs, $v, null, $args['id']);
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
        $body = [
            'name' => trim((string) ($b['name'] ?? '')), 'nameBengali' => trim((string) ($b['nameBengali'] ?? '')), 'address' => trim((string) ($b['address'] ?? '')),
            'email' => trim((string) ($b['email'] ?? '')), 'city' => trim((string) ($b['city'] ?? '')), 'state' => trim((string) ($b['state'] ?? '')),
            'pincode' => trim((string) ($b['pincode'] ?? '')), 'gstNo' => strtoupper(trim((string) ($b['gstNo'] ?? ''))), 'panNo' => strtoupper(trim((string) ($b['panNo'] ?? ''))),
            'notes' => trim((string) ($b['notes'] ?? '')), 'membershipStatus' => ($b['membershipStatus'] ?? '') === 'VIP' ? 'VIP' : 'Regular',
        ];
        $contacts = [];
        foreach (['phone1' => 'whatsapp', 'phone2' => 'mobile'] as $k => $label) {
            $n = preg_replace('/\D/', '', (string) ($b[$k] ?? ''));
            if ($n !== '') {
                $contacts[] = ['number' => strlen($n) > 10 ? substr($n, -10) : $n, 'label' => $label];
            }
        }
        if ($id === null) {
            $body['contacts'] = $contacts;
            if (!empty($b['force'])) {
                $body['force'] = true;
            }
        } else {
            // the two numbers on the form replace the first two; any further numbers already saved stay (the server keeps them)
            $cur = $this->api()->get('directory/customers/' . rawurlencode($id))['data']['profile']['contacts'] ?? [];
            $body['contacts'] = array_merge($contacts, array_slice((array) $cur, 2));
            $body['expectedUpdatedAt'] = (string) ($b['expectedUpdatedAt'] ?? '');
        }
        try {
            $r = $id === null ? $this->api()->post('directory/customers', $body) : $this->api()->put('directory/customers/' . rawurlencode($id) . '/partial', $body);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $dupe = $e->status === 409 && str_contains($e->getMessage(), 'already');
            return $this->form($rq, $rs->withStatus(422), $b, $e->getMessage(), $id, $dupe && $id === null);
        }
        $cust = $r['data'] ?? [];
        $this->flash('success', $id === null ? 'Customer saved' : 'Customer updated');
        return $this->redirect($rs, '/directory/customers/' . rawurlencode((string) ($cust['_id'] ?? $id)));
    }

    private function form(Request $rq, Response $rs, array $v, ?string $error, ?string $id, bool $canForce = false): Response
    {
        return $this->view($rq, $rs, 'directory/form.twig', ['v' => $v, 'error' => $error, 'id' => $id, 'canForce' => $canForce, 'active' => 'directory']);
    }
}
