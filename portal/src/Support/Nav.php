<?php
declare(strict_types=1);

namespace Portal\Support;

use Portal\Auth\Session;

/**
 * The side menu. One list, filtered by what the signed-in person may see (permissions come from the API).
 * `ready` = the page exists; the others show a small "Soon" tag so the menu already looks like the finished portal.
 */
final class Nav
{
    // 'color' matches the tile colour the SAME feature has on the app's Home screen (home_screen.dart), so the two feel
    // like one product. Admin Control has no app counterpart, so those few use a colour in the same spirit.
    private const ITEMS = [
        ['section' => '', 'items' => [
            ['key' => 'home', 'label' => 'Home', 'icon' => 'home', 'href' => '/', 'perm' => null, 'ready' => true, 'color' => '#E94560'],
        ]],
        ['section' => 'Sell', 'items' => [
            ['key' => 'billing', 'label' => 'GST Billing', 'icon' => 'receipt', 'href' => '/billing', 'perm' => 'billing.view', 'ready' => true, 'color' => '#B45309'],
            ['key' => 'estimates', 'label' => 'Estimates', 'icon' => 'quote', 'href' => '/estimates', 'perm' => 'estimates.view', 'ready' => true, 'color' => '#7C3AED'],
            ['key' => 'orders', 'label' => 'Orders', 'icon' => 'hammer', 'href' => '/orders', 'perm' => 'orders.view', 'ready' => true, 'color' => '#0E7490'],
            ['key' => 'dues', 'label' => 'Pending dues', 'icon' => 'hourglass', 'href' => '/dues', 'perm' => 'billing.view', 'ready' => true, 'color' => '#DC2626'],
        ]],
        ['section' => 'Stock', 'items' => [
            ['key' => 'stock', 'label' => 'Stock', 'icon' => 'gem', 'href' => '/stock', 'perm' => 'items.view', 'ready' => true, 'color' => '#11998E'],
            ['key' => 'summary', 'label' => 'Stock Summary', 'icon' => 'scale', 'href' => '/stock/summary', 'perm' => 'stock.view', 'ready' => true, 'color' => '#0D9488'],
            ['key' => 'oldmetal', 'label' => 'Old Metal', 'icon' => 'recycle', 'href' => '/old-metal', 'perm' => 'oldMetal.view', 'ready' => true, 'color' => '#B45309'],
            ['key' => 'purchases', 'label' => 'Purchases', 'icon' => 'truck', 'href' => '/purchases', 'perm' => 'purchases.view', 'ready' => true, 'color' => '#059669'],
            ['key' => 'tally', 'label' => 'Stock Tally', 'icon' => 'check', 'href' => '/tally', 'perm' => 'tally.view', 'ready' => true, 'color' => '#0EA5E9'],
        ]],
        ['section' => 'Money', 'items' => [
            ['key' => 'daybook', 'label' => 'Day Book', 'icon' => 'book', 'href' => '/day-book', 'perm' => 'daybook.view', 'ready' => true, 'color' => '#0F766E'],
            ['key' => 'expenses', 'label' => 'Expenses', 'icon' => 'wallet', 'href' => '/expenses', 'perm' => 'expenses.view', 'ready' => true, 'color' => '#7C3AED'],
            ['key' => 'gst', 'label' => 'GST Summary', 'icon' => 'chart', 'href' => '/gst', 'perm' => 'gst.viewReports', 'ready' => true, 'color' => '#4F46E5'],
            ['key' => 'reports', 'label' => 'Reports', 'icon' => 'bars', 'href' => '/reports', 'perm' => 'reports.view', 'ready' => true, 'color' => '#DB2777'],
        ]],
        ['section' => 'People', 'items' => [
            ['key' => 'directory', 'label' => 'Customers & suppliers', 'icon' => 'users', 'href' => '/directory', 'perm' => 'directory.view', 'ready' => true, 'color' => '#2563EB'],
        ]],
        ['section' => 'Admin Control', 'admin' => true, 'items' => [
            ['key' => 'staff', 'label' => 'Staff & roles', 'icon' => 'shield', 'href' => '/admin/staff', 'perm' => 'users.manage', 'ready' => true, 'color' => '#2563EB'],
            ['key' => 'updates', 'label' => 'App updates', 'icon' => 'phone', 'href' => '/admin/updates', 'perm' => 'appUpdate.manage', 'ready' => true, 'color' => '#4F46E5'],
            ['key' => 'loginscreen', 'label' => 'Login screen', 'icon' => 'image', 'href' => '/admin/login-screen', 'perm' => 'appAssets.manage', 'ready' => true, 'color' => '#9333EA'],
            ['key' => 'notify', 'label' => 'Notifications', 'icon' => 'bell', 'href' => '/admin/notifications', 'perm' => 'notifications.send', 'ready' => true, 'color' => '#D97706'],
            ['key' => 'settings', 'label' => 'App settings', 'icon' => 'sliders', 'href' => '/admin/settings', 'perm' => 'settings.manageStockRules', 'ready' => true, 'color' => '#0F766E'],
            ['key' => 'audit', 'label' => 'Audit log', 'icon' => 'list', 'href' => '/admin/audit', 'perm' => 'users.manage', 'ready' => true, 'color' => '#475569'],
            ['key' => 'server', 'label' => 'Server status', 'icon' => 'chart', 'href' => '/admin/server', 'perm' => 'users.manage', 'ready' => true, 'color' => '#059669'],
            ['key' => 'backup', 'label' => 'Data backup', 'icon' => 'download', 'href' => '/admin/backup', 'perm' => 'users.manage', 'adminOnly' => true, 'ready' => true, 'color' => '#0369A1'],
        ]],
    ];

    /** Every item, for registering the routes (not filtered by person). */
    public static function forAll(): array
    {
        $all = [];
        foreach (self::ITEMS as $g) {
            foreach ($g['items'] as $it) {
                $all[] = $it;
            }
        }
        return $all;
    }

    /** {icon, color} of a menu key, for showing that page's own colour and icon outside the menu (e.g. the top bar). */
    public static function meta(string $key): array
    {
        foreach (self::forAll() as $it) {
            if ($it['key'] === $key) {
                return ['icon' => $it['icon'], 'color' => $it['color'] ?? '#6b7280'];
            }
        }
        return ['icon' => 'list', 'color' => '#6b7280'];
    }

    /** @return array<int,array{section:string,admin:bool,items:array}> the menu for the current person */
    public static function forUser(): array
    {
        $out = [];
        foreach (self::ITEMS as $group) {
            $items = [];
            foreach ($group['items'] as $it) {
                if (!empty($it['adminOnly']) && !Session::isAdmin()) {
                    continue;   // not a permission anyone can be handed: only the Admin / Owner
                }
                if ($it['perm'] === null || Session::can($it['perm'])) {
                    $items[] = $it;
                }
            }
            if ($items) {
                $out[] = ['section' => $group['section'], 'admin' => !empty($group['admin']), 'items' => $items];
            }
        }
        return $out;
    }
}
