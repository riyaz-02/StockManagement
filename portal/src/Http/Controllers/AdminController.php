<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Admin Control: app updates, notifications, shop rules (settings), the audit log and the server's health. */
final class AdminController extends BaseController
{
    // ── app updates ───────────────────────────────────────────────────────────────────────────

    /** Current config + who published what, when (the audit log already keeps this — nothing extra to store). */
    private function updatesContext(): array
    {
        $cur = (array) ($this->api()->get('app-version')['data']['appVersion'] ?? []);
        $history = [];
        try {
            $history = (array) ($this->api()->get('admin/audit', ['entity' => 'app_update', 'limit' => 8])['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return ['cur' => $cur + ['updateMessage' => '', 'downloadUrl' => '', 'forceUpdate' => false, 'maintenanceMode' => ['enabled' => false, 'message' => '']], 'history' => $history];
    }

    public function updates(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'admin/updates.twig', $this->updatesContext() + ['v' => [], 'mv' => [], 'error' => null, 'mError' => null, 'active' => 'updates']);
    }

    public function publishUpdate(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->put('app-version', [
                'latestVersion' => trim((string) ($b['latestVersion'] ?? '')), 'latestVersionCode' => (string) ($b['latestVersionCode'] ?? ''),
                'downloadUrl' => trim((string) ($b['downloadUrl'] ?? '')), 'updateMessage' => trim((string) ($b['updateMessage'] ?? '')), 'forceUpdate' => !empty($b['forceUpdate']),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->view($rq, $rs->withStatus(422), 'admin/updates.twig', $this->updatesContext() + ['v' => $b, 'mv' => [], 'error' => $e->getMessage(), 'mError' => null, 'active' => 'updates']);
        }
        $this->flash('success', 'Update published. Every phone that is open is told now.');
        return $this->redirect($rs, '/admin/updates');
    }

    /** The sign-in gate: on/off + the message shown while it is on. Admin/owner can always still sign in. */
    public function updateMaintenance(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->put('app-version/maintenance', ['enabled' => !empty($b['enabled']), 'message' => trim((string) ($b['message'] ?? ''))]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->view($rq, $rs->withStatus(422), 'admin/updates.twig', $this->updatesContext() + ['v' => [], 'mv' => $b, 'error' => null, 'mError' => $e->getMessage(), 'active' => 'updates']);
        }
        $this->flash('success', !empty($b['enabled']) ? 'Sign-ins are gated. Admin and Owner can still get in.' : 'Sign-ins are open again.');
        return $this->redirect($rs, '/admin/updates');
    }

    // ── notifications ─────────────────────────────────────────────────────────────────────────

    public function notifications(Request $rq, Response $rs): Response
    {
        $rows = [];
        try {
            $rows = (array) ($this->api()->get('notifications')['data']['notifications'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'admin/notifications.twig', ['rows' => $rows, 'v' => ['target' => 'all'], 'error' => null, 'active' => 'notify']);
    }

    public function sendNotification(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        $role = (string) ($b['target'] ?? 'all');
        try {
            $r = $this->api()->post('notifications/send', [
                'title' => trim((string) ($b['title'] ?? '')), 'body' => trim((string) ($b['body'] ?? '')),
                'targetType' => $role === 'all' ? 'all' : 'role', 'targetRole' => $role === 'all' ? null : $role,
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $rows = (array) ($this->api()->get('notifications')['data']['notifications'] ?? []);
            return $this->view($rq, $rs->withStatus(422), 'admin/notifications.twig', ['rows' => $rows, 'v' => $b, 'error' => $e->getMessage(), 'active' => 'notify']);
        }
        $this->flash('success', (string) ($r['message'] ?? 'Sent'));
        return $this->redirect($rs, '/admin/notifications');
    }

    // ── settings: the shop rules ──────────────────────────────────────────────────────────────

    public function settings(Request $rq, Response $rs): Response
    {
        $d = (array) ($this->api()->get('stock-settings')['data'] ?? []);
        return $this->view($rq, $rs, 'admin/settings.twig', ['d' => $d, 'labels' => self::LABELS, 'active' => 'settings']);
    }

    public function saveSettings(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        $body = [];
        foreach ((array) ($b['s'] ?? []) as $group => $fields) {
            foreach ((array) $fields as $key => $val) {
                $val = (string) $val;
                if ($val === 'true' || $val === 'false') {
                    $body[$group][$key] = $val === 'true';
                } elseif ($group === 'hallmark' && $key !== 'type') {
                    $body[$group][$key] = $val;
                } else {
                    $body[$group][$key] = $val;
                }
            }
        }
        try {
            $this->api()->put('stock-settings', $body);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $this->flash('error', $e->getMessage());
            return $this->redirect($rs, '/admin/settings');
        }
        $this->flash('success', 'Rules saved. New prices use them straight away.');
        return $this->redirect($rs, '/admin/settings');
    }

    public function resetSettings(Request $rq, Response $rs): Response
    {
        try {
            $this->api()->post('stock-settings/reset', []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $this->refreshWith($rs, 'success', 'Rules are back to the standard ones');
    }

    // ── audit log ─────────────────────────────────────────────────────────────────────────────

    public function audit(Request $rq, Response $rs): Response
    {
        $page = max(1, (int) $this->q($rq, 'page', '1'));
        $entity = $this->q($rq, 'entity');
        $q = $this->q($rq, 'q');
        $from = $this->q($rq, 'from');
        $to = $this->q($rq, 'to');
        $r = $this->api()->get('admin/audit', array_filter(['entity' => $entity, 'q' => $q, 'from' => $from, 'to' => $to, 'page' => $page, 'limit' => 40], fn ($v) => $v !== ''));
        return $this->view($rq, $rs, 'admin/audit.twig', [
            'rows' => $r['data'] ?? [], 'pg' => $r['pagination'] ?? [], 'page' => $page, 'entity' => $entity, 'q' => $q, 'from' => $from, 'to' => $to, 'active' => 'audit',
            'kinds' => [
                '' => 'Everything',
                'invoice' => 'GST bills', 'credit_note' => 'Returns / refunds', 'estimate' => 'Estimates', 'order' => 'Customer orders',
                'stock_item' => 'Stock', 'bulk_stock' => 'Bulk stock', 'purchase' => 'Purchases', 'old_metal' => 'Old metal', 'tally' => 'Stock tally', 'expense' => 'Expenses', 'gst_filing' => 'GST filings',
                'backup' => 'Data backups', 'user' => 'Staff logins', 'permission' => 'Permissions', 'app_update' => 'App updates', 'notification' => 'Notifications', 'settings' => 'Rules',
                'customer' => 'Customers', 'supplier' => 'Suppliers', 'karigar' => 'Karigars', 'staff' => 'Staff profiles',
            ],
        ]);
    }

    // ── server ────────────────────────────────────────────────────────────────────────────────

    public function server(Request $rq, Response $rs): Response
    {
        $st = [];
        $problem = null;
        try {
            $st = (array) ($this->api()->get('admin/status')['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $problem = $e->getMessage();
        }
        return $this->view($rq, $rs, 'admin/server.twig', ['st' => $st, 'problem' => $problem, 'active' => 'server']);
    }

    /** Plain words for the shop rules (the keys are the server's own names). group.key => [label, help] */
    private const LABELS = [
        'addStock.customerWastage' => ['Customer wastage is worked on', 'The weight the customer wastage % is taken from when a piece is added.'],
        'addStock.valuation' => ['Metal value is worked on', 'The weight that is multiplied by the rate to price the metal in a piece.'],
        'addStock.makingCharges' => ['Making is worked on', 'The weight that is multiplied by the making rate per gram.'],
        'addStock.labourCharges' => ['Labour is worked on', 'The weight that is multiplied by the labour rate per gram.'],
        'addStock.metalRateByPurity' => ['Rate depends on purity', 'Use a different rate for each purity.'],
        'addStock.hallmarkGst' => ['GST on the hallmark fee', 'Charge GST on the hallmarking fee of a piece.'],
        'addStock.calculateItemRate' => ['Item rate is worked out', 'How the rate of a piece is decided.'],
        'sellStock.reverseCalculation' => ['When a price is typed, change', 'Which figure moves when the price is fixed by hand.'],
        'sellStock.makingChargesType' => ['Making charge on a bill comes from', 'Use the one on the piece, or the last time the same piece was sold.'],
        'sellStock.metalRateByPurity' => ['Rate depends on purity', 'Use a different rate for each purity when selling.'],
        'sellStock.byAddedMetalRate' => ['Use the rate the piece was added at', 'Price by the metal rate of the day it was added.'],
        'sellStock.custWastage' => ['Customer wastage on a bill comes from', 'Use the one on the piece, the last sale, or leave it blank.'],
        'sellStock.hallmarkGst' => ['GST on the hallmark fee', 'Charge GST on the hallmarking fee when selling.'],
        'purchase.labourCharges' => ['Labour on purchases is worked on', 'The weight the supplier labour rate is multiplied by.'],
        'purchase.wastage' => ['Wastage on purchases is worked on', 'The weight the wastage % is taken from.'],
        'purchase.finalValuation' => ['Purchase value is worked on', 'The weight multiplied by the purchase rate.'],
        'purchase.hallmarkGst' => ['GST on the hallmark fee', 'Charge GST on the hallmarking fee of a purchase.'],
        'oldMetal.receivedValuation' => ['Old metal from customers is valued on', 'The weight used to value old gold or silver you take.'],
        'oldMetal.rawMetalPurchaseValuation' => ['Raw metal you buy is valued on', 'The weight used to value raw metal you buy.'],
        'hallmark.type' => ['Hallmark fee is charged', 'Per piece, or per gram.'],
        'hallmark.charge' => ['Hallmark fee (rupees)', 'The fee for hallmarking.'],
        'hallmark.cgst' => ['Hallmark fee CGST %', 'GST on the fee within the state.'],
        'hallmark.sgst' => ['Hallmark fee SGST %', 'GST on the fee within the state.'],
        'hallmark.igst' => ['Hallmark fee IGST %', 'GST on the fee to another state.'],
    ];
}
