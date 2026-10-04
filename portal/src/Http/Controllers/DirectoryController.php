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
    // One form (templates/directory/customer_form.twig) in a pop-up, opened from any page, or on a page when opened directly.

    private const LABELS = ['whatsapp', 'mobile', 'home', 'work', 'other'];
    private const NOTIFY = ['all', 'offers', 'invitations', 'none'];

    public function newForm(Request $rq, Response $rs): Response
    {
        return $this->form($rq, $rs, ['numbers' => [['number' => '', 'label' => 'whatsapp']]], null, null);
    }

    public function editForm(Request $rq, Response $rs, array $args): Response
    {
        $c = $this->api()->get('directory/customers/' . rawurlencode($args['id']))['data'] ?? [];
        $p = (array) ($c['profile'] ?? []);
        $numbers = [];
        foreach ((array) ($p['contacts'] ?? []) as $k) {
            $numbers[] = ['number' => (string) ($k['number'] ?? ''), 'label' => (string) ($k['label'] ?? 'mobile')];
        }
        if (!$numbers) {
            foreach (['whatsapp_no' => 'whatsapp', 'mobile_no' => 'mobile', 'mobile_no_3' => 'mobile', 'mobile_no_4' => 'mobile'] as $f => $label) {
                if (!empty($c[$f])) {
                    $numbers[] = ['number' => (string) $c[$f], 'label' => $label];
                }
            }
        }
        $ref = (array) ($p['referredBy'] ?? []);
        // the saved special dates (the website's `anniversaries`); a birth date / anniversary kept only in the app profile joins them
        $dates = [];
        foreach ((array) ($c['anniversaries'] ?? []) as $a) {
            $dates[] = ['occasion' => (string) ($a['occasion'] ?? ''), 'date' => substr((string) ($a['date'] ?? ''), 0, 10)];
        }
        foreach ([['dob', 'Birthday', '/birth/i'], ['anniversary', 'Marriage Anniversary', '/^(?!.*(work|job|business)).*(marriage|wedding|anniversary)/i']] as [$f, $label, $re]) {
            $have = false;
            foreach ($dates as $d) {
                $have = $have || preg_match($re, $d['occasion']) === 1;
            }
            if (!empty($p[$f]) && !$have) {
                $dates[] = ['occasion' => $label, 'date' => substr((string) $p[$f], 0, 10)];
            }
        }
        $v = [
            'dates' => $dates,
            'name' => $c['customer_name'] ?? '', 'nameBengali' => $c['customer_name_bengali'] ?? '', 'address' => $c['address'] ?? '',
            'addressBengali' => ($p['addressBn'] ?? '') ?: ($c['address_bengali'] ?? ''),
            'numbers' => $numbers ?: [['number' => '', 'label' => 'whatsapp']],
            'notificationType' => in_array($c['notification_type'] ?? 'all', self::NOTIFY, true) ? $c['notification_type'] : 'all',
            'email' => $c['email'] ?? '', 'membershipStatus' => $p['membershipStatus'] ?? 'Regular',
            'city' => $p['city'] ?? '', 'state' => $p['state'] ?? '', 'pincode' => $p['pincode'] ?? '', 'gstNo' => $p['gstNo'] ?? '', 'panNo' => $p['panNo'] ?? '', 'notes' => $p['notes'] ?? '',
            'referredById' => isset($ref['customerId']) ? (string) $ref['customerId'] : '',
            'referredByLabel' => isset($ref['customerId']) ? trim(($ref['name'] ?? '') . (isset($ref['code']) ? ' · ' . $ref['code'] : '')) : '',
            'referredByText' => !isset($ref['customerId']) ? (string) ($ref['text'] ?? '') : '',
            'expectedUpdatedAt' => $c['updated_at'] ?? '',
        ];
        $v['openMore'] = ($v['email'] . $v['city'] . $v['state'] . $v['pincode'] . $v['gstNo'] . $v['panNo'] . $v['notes']) !== '' || $v['membershipStatus'] === 'VIP';
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

    /** The phone numbers of the form (number[] + label[]): digits only, the last 10 of a longer one (+91 ...), blanks dropped. */
    private function contactsOf(array $b): array
    {
        $labels = (array) ($b['label'] ?? []);
        $out = [];
        foreach ((array) ($b['number'] ?? []) as $i => $raw) {
            $n = preg_replace('/\D/', '', (string) $raw);
            if ($n === '') {
                continue;
            }
            $n = strlen($n) > 10 ? substr($n, -10) : $n;
            $label = (string) ($labels[$i] ?? 'mobile');
            $out[] = ['number' => $n, 'label' => in_array($label, self::LABELS, true) ? $label : 'mobile'];
        }
        return $out;
    }

    /** The "special dates" of the form (dateOccasion[] + dateValue[]): blank rows dropped. */
    private function datesOf(array $b): array
    {
        $dates = (array) ($b['dateValue'] ?? []);
        $out = [];
        foreach ((array) ($b['dateOccasion'] ?? []) as $i => $occasion) {
            $o = trim((string) $occasion);
            $d = trim((string) ($dates[$i] ?? ''));
            if ($o === '' && $d === '') {
                continue;
            }
            $out[] = ['occasion' => $o, 'date' => $d];
        }
        return $out;
    }

    private function save(Request $rq, Response $rs, ?string $id): Response
    {
        $b = $this->input($rq);
        $t = static fn (string $k): string => trim((string) ($b[$k] ?? ''));
        $body = [
            'name' => $t('name'), 'nameBengali' => $t('nameBengali'), 'address' => $t('address'), 'addressBengali' => $t('addressBengali'),
            'email' => $t('email'), 'city' => $t('city'), 'state' => $t('state'), 'pincode' => $t('pincode'),
            'gstNo' => strtoupper($t('gstNo')), 'panNo' => strtoupper($t('panNo')), 'notes' => $t('notes'),
            'membershipStatus' => $t('membershipStatus') === 'VIP' ? 'VIP' : 'Regular',
            'notificationType' => in_array($t('notificationType'), self::NOTIFY, true) ? $t('notificationType') : 'all',
            'contacts' => $this->contactsOf($b),
            'importantDates' => $this->datesOf($b),
        ];
        if ($t('referredById') !== '') {
            $body['referredById'] = $t('referredById');
        } else {
            $body['referredByText'] = $t('referredByText');
        }
        if ($id === null) {
            if (!empty($b['force'])) {
                $body['force'] = true;
            }
        } else {
            $body['expectedUpdatedAt'] = $t('expectedUpdatedAt');
            if (!empty($b['force'])) {
                $body['force'] = true;
            }
        }
        try {
            $r = $id === null ? $this->api()->post('directory/customers', $body) : $this->api()->put('directory/customers/' . rawurlencode($id) . '/partial', $body);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $dupe = $e->status === 409 && str_contains($e->getMessage(), 'number');
            $v = $b;
            $v['numbers'] = $this->contactsOf($b) ?: [['number' => '', 'label' => 'whatsapp']];
            $v['referredByLabel'] = (string) ($b['referredByLabel'] ?? '');
            $v['dates'] = $this->datesOf($b);
            $v['openMore'] = true;
            return $this->form($rq, $rs->withStatus(422), $v, $e->getMessage(), $id, $dupe);
        }
        $cust = (array) ($r['data'] ?? []);
        $cid = (string) ($cust['_id'] ?? $id);
        if ($this->isHx($rq)) {
            if ($id !== null) {
                $this->flash('success', 'Customer updated');
                return $rs->withStatus(204)->withHeader('HX-Redirect', '/directory/customers/' . rawurlencode($cid));
            }
            $mobile = (string) ($body['contacts'][0]['number'] ?? '');
            return $rs->withStatus(204)->withHeader('HX-Trigger', json_encode([
                'modal-close' => true,
                'customer-saved' => ['id' => $cid, 'name' => $body['name'], 'mobile' => $mobile],
                'toast' => ['type' => 'success', 'text' => 'Customer saved: ' . $body['name']],
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        }
        $this->flash('success', $id === null ? 'Customer saved' : 'Customer updated');
        return $this->redirect($rs, '/directory/customers/' . rawurlencode($cid));
    }

    private function form(Request $rq, Response $rs, array $v, ?string $error, ?string $id, bool $canForce = false): Response
    {
        $modal = $this->isHx($rq);
        return $this->view($rq, $rs, $modal ? 'directory/customer_form.twig' : 'directory/form.twig', ['v' => $v, 'error' => $error, 'id' => $id, 'canForce' => $canForce, 'modal' => $modal, 'active' => 'directory']);
    }

    // ── what the form asks for while it is being filled in (JSON) ────────────────────────────

    /** Customers matching a number / name / customer ID (live duplicate warning, "referred by"). */
    public function lookup(Request $rq, Response $rs): Response
    {
        $q = $this->q($rq, 'q');
        $rows = [];
        if ($q !== '') {
            try {
                $rows = (array) ($this->api()->get('directory/customers/lookup', array_filter(['q' => $q, 'exclude' => $this->q($rq, 'exclude')], fn ($x) => $x !== ''), 8)['data'] ?? []);
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        return $this->json($rs, ['results' => $rows]);
    }

    /** English -> Bengali for the name / address fields (done by the server, never by the browser). */
    public function translate(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        $texts = array_filter(['name' => trim((string) ($b['name'] ?? '')), 'address' => trim((string) ($b['address'] ?? ''))], fn ($x) => $x !== '');
        $out = [];
        if ($texts) {
            try {
                $out = (array) ($this->api()->post('directory/translate', $texts, 12)['data'] ?? []);
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        return $this->json($rs, ['translations' => $out]);
    }

    private function json(Response $rs, array $data): Response
    {
        $rs->getBody()->write((string) json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        return $rs->withHeader('Content-Type', 'application/json')->withHeader('Cache-Control', 'no-store');
    }
}
