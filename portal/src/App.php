<?php
declare(strict_types=1);

namespace Portal;

use Portal\Auth\Session;
use Portal\Http\Controllers\AdminController;
use Portal\Http\Controllers\AdminStaffController;
use Portal\Http\Controllers\BackupController;
use Portal\Http\Controllers\AuthController;
use Portal\Http\Controllers\BillingController;
use Portal\Http\Controllers\EstimateController;
use Portal\Http\Controllers\DayBookController;
use Portal\Http\Controllers\DirectoryController;
use Portal\Http\Controllers\DuesController;
use Portal\Http\Controllers\ExpenseController;
use Portal\Http\Controllers\GstController;
use Portal\Http\Controllers\HomeController;
use Portal\Http\Controllers\LookupController;
use Portal\Http\Controllers\OldMetalController;
use Portal\Http\Controllers\OrderController;
use Portal\Http\Controllers\LiveController;
use Portal\Http\Controllers\PageController;
use Portal\Http\Controllers\PurchaseController;
use Portal\Http\Controllers\RateController;
use Portal\Http\Controllers\ReportsController;
use Portal\Http\Controllers\BellController;
use Portal\Http\Controllers\WorkplaceController;
use Portal\Http\Controllers\AdminBranchController;
use Portal\Http\Controllers\StockController;
use Portal\Http\Controllers\StockSummaryController;
use Portal\Http\Controllers\WastageController;
use Portal\Http\Controllers\TallyController;
use Portal\Http\Controllers\WakeController;
use Portal\Http\Middleware\CsrfGuard;
use Portal\Http\Middleware\RequireAuth;
use Portal\Http\Middleware\SecurityHeaders;
use Portal\Support\I18n;
use Portal\Support\Nav;
use Portal\Support\TwigExtension;
use Slim\App as SlimApp;
use Slim\Factory\AppFactory;
use Slim\Views\Twig;
use Slim\Views\TwigMiddleware;

/** Builds the web application: routes, templates, middleware. public/index.php runs it. */
final class App
{
    public static function create(string $root): SlimApp
    {
        Config::load($root);
        date_default_timezone_set('Asia/Kolkata');
        Session::start();
        I18n::load((string) (Session::user()['language'] ?? 'en'));

        $app = AppFactory::create();
        $twig = Twig::create(Config::path('templates'), [
            'cache' => Config::isDev() ? false : Config::path('storage/twig'),
            'autoescape' => 'html',
            'strict_variables' => Config::isDev(),
        ]);
        $twig->addExtension(new TwigExtension());

        $app->add(new CsrfGuard());
        $app->addBodyParsingMiddleware();
        $app->add(TwigMiddleware::create($app, $twig));
        $app->add(new SecurityHeaders());
        $app->addRoutingMiddleware();
        $errors = $app->addErrorMiddleware(Config::isDev(), true, true);
        $errors->setDefaultErrorHandler(new ErrorHandler($app->getResponseFactory(), $twig));

        $auth = new RequireAuth();

        // public
        $app->get('/ping', fn ($rq, $rs) => (function ($rs) { $rs->getBody()->write('ok'); return $rs; })($rs));
        $app->get('/login', [AuthController::class, 'showLogin']);
        $app->post('/login', [AuthController::class, 'login']);
        $app->post('/logout', [AuthController::class, 'logout']);
        $app->get('/wake', [WakeController::class, 'page']);
        $app->get('/wake/status', [WakeController::class, 'status']);
        $app->post('/wake/start', [WakeController::class, 'start']);

        // signed-in
        $app->get('/', [HomeController::class, 'index'])->add($auth);
        $app->get('/partials/dashboard', [HomeController::class, 'stats'])->add($auth);
        $app->get('/partials/rate', [RateController::class, 'strip'])->add($auth);
        $app->get('/partials/rate-form', [RateController::class, 'form'])->add(new RequireAuth('rates.edit'));
        $app->post('/rates', [RateController::class, 'save'])->add(new RequireAuth('rates.edit'));
        $app->get('/partials/workplace', [WorkplaceController::class, 'show'])->add($auth);
        $app->post('/workplace', [WorkplaceController::class, 'save'])->add($auth);
        $app->get('/partials/bell/count', [BellController::class, 'count'])->add($auth);
        $app->get('/partials/bell/list', [BellController::class, 'list'])->add($auth);
        $app->post('/partials/bell/seen', [BellController::class, 'seen'])->add($auth);
        $app->post('/live/ticket', [LiveController::class, 'ticket'])->add($auth);
        $app->post('/session/refresh', [LiveController::class, 'refresh'])->add($auth);
        $app->post('/presence/ping', [LiveController::class, 'ping'])->add($auth);

        $need = fn (string $perm) => new RequireAuth($perm);
        $app->get('/lookup/customers', [LookupController::class, 'customers'])->add($auth);

        // Day Book
        $app->get('/day-book', [DayBookController::class, 'index'])->add($need('daybook.view'));
        $app->get('/day-book/body', [DayBookController::class, 'body'])->add($need('daybook.view'));

        // Expenses
        $app->get('/expenses', [ExpenseController::class, 'index'])->add($need('expenses.view'));
        $app->get('/expenses/list', [ExpenseController::class, 'list'])->add($need('expenses.view'));
        $app->get('/expenses/new', [ExpenseController::class, 'form'])->add($need('expenses.create'));
        $app->post('/expenses', [ExpenseController::class, 'create'])->add($need('expenses.create'));
        $app->post('/expenses/{id}/cancel', [ExpenseController::class, 'cancel'])->add($need('expenses.delete'));

        // Pending dues
        $app->get('/dues', [DuesController::class, 'index'])->add($need('billing.view'));
        $app->get('/dues/list', [DuesController::class, 'list'])->add($need('billing.view'));
        $app->get('/dues/pay/{id}', [DuesController::class, 'payForm'])->add($need('billing.receivePayment'));
        $app->post('/dues/pay/{id}', [DuesController::class, 'pay'])->add($need('billing.receivePayment'));

        // Orders
        $app->get('/orders', [OrderController::class, 'index'])->add($need('orders.view'));
        $app->get('/orders/list', [OrderController::class, 'list'])->add($need('orders.view'));
        $app->get('/orders/new', [OrderController::class, 'newForm'])->add($need('orders.create'));
        $app->post('/orders', [OrderController::class, 'create'])->add($need('orders.create'));
        $app->get('/orders/{id}', [OrderController::class, 'show'])->add($need('orders.view'));
        $app->get('/orders/{id}/advance', [OrderController::class, 'advanceForm'])->add($need('orders.create'));
        $app->post('/orders/{id}/advance', [OrderController::class, 'advance'])->add($need('orders.create'));
        $app->post('/orders/{id}/status', [OrderController::class, 'status'])->add($need('orders.create'));
        $app->get('/orders/{id}/cancel', [OrderController::class, 'cancelForm'])->add($need('orders.cancel'));
        $app->post('/orders/{id}/cancel', [OrderController::class, 'cancel'])->add($need('orders.cancel'));

        // GST bills
        $app->get('/billing', [BillingController::class, 'index'])->add($need('billing.view'));
        $app->get('/billing/list', [BillingController::class, 'list'])->add($need('billing.view'));
        $app->get('/billing/new', [BillingController::class, 'newForm'])->add($need('billing.create'));
        $app->get('/billing/row', [BillingController::class, 'row'])->add($need('billing.create'));
        $app->get('/billing/stock-row', [BillingController::class, 'stockRow'])->add($need('billing.create'));
        $app->get('/billing/stock-search', [BillingController::class, 'stockSearch'])->add($need('billing.create'));
        $app->get('/billing/customer-by-mobile', [BillingController::class, 'customerByMobile'])->add($need('billing.create'));
        $app->get('/billing/cash-room', [BillingController::class, 'cashRoom'])->add($need('billing.create'));
        $app->post('/billing/calc', [BillingController::class, 'calc'])->add($need('billing.create'));
        $app->get('/billing/old-metal', [BillingController::class, 'oldMetal'])->add($need('billing.create'));
        $app->post('/billing', [BillingController::class, 'create'])->add($need('billing.create'));
        $app->get('/billing/{id}', [BillingController::class, 'show'])->add($need('billing.view'));
        $app->get('/billing/{id}/print', [BillingController::class, 'print'])->add($need('billing.view'));
        $app->get('/billing/{id}/return', [BillingController::class, 'returnForm'])->add($need('billing.creditNote'));
        $app->post('/billing/{id}/return/preview', [BillingController::class, 'returnPreview'])->add($need('billing.creditNote'));
        $app->post('/billing/{id}/return', [BillingController::class, 'returnSave'])->add($need('billing.creditNote'));

        // Estimates
        $app->get('/estimates', [EstimateController::class, 'index'])->add($need('estimates.view'));
        $app->get('/estimates/list', [EstimateController::class, 'list'])->add($need('estimates.view'));
        $app->get('/estimates/new', [BillingController::class, 'estimateForm'])->add($need('estimates.create'));
        $app->post('/estimates', [BillingController::class, 'estimateCreate'])->add($need('estimates.create'));
        $app->get('/estimates/{id}', [EstimateController::class, 'show'])->add($need('estimates.view'));
        $app->get('/estimates/{id}/print', [EstimateController::class, 'print'])->add($need('estimates.view'));
        $app->delete('/estimates/{id}', [EstimateController::class, 'cancel'])->add($need('estimates.create'));

        // Stock
        $app->get('/stock', [StockController::class, 'index'])->add($need('items.view'));
        $app->get('/stock/list', [StockController::class, 'list'])->add($need('items.view'));
        $app->get('/stock/summary', [StockSummaryController::class, 'index'])->add($need('stock.view'));
        $app->post('/stock/summary/snapshot', [StockSummaryController::class, 'snapshot'])->add($need('stock.snapshot'));
        $app->get('/stock/summary/movements', [StockSummaryController::class, 'movements'])->add($need('stock.view'));
        $app->get('/stock/summary/history', [StockSummaryController::class, 'history'])->add($need('stock.view'));
        $app->get('/stock/summary/history.csv', [StockSummaryController::class, 'historyCsv'])->add($need('stock.view'));
        $app->get('/stock/summary/wastage', [WastageController::class, 'panel'])->add($need('wastage.view'));
        $app->get('/stock/wastage', [WastageController::class, 'index'])->add($need('wastage.view'));
        $app->get('/stock/wastage/new', [WastageController::class, 'newForm'])->add($need('wastage.report'));
        $app->post('/stock/wastage', [WastageController::class, 'save'])->add($need('wastage.report'));
        $app->get('/stock/wastage/{id}', [WastageController::class, 'show'])->add($need('wastage.view'));
        $app->get('/stock/wastage/{id}/edit', [WastageController::class, 'editForm'])->add($need('wastage.report'));
        $app->post('/stock/wastage/{id}', [WastageController::class, 'save'])->add($need('wastage.report'));
        $app->post('/stock/wastage/{id}/approve', [WastageController::class, 'approve'])->add($need('wastage.approve'));
        $app->get('/stock/wastage/{id}/reject', [WastageController::class, 'rejectForm'])->add($need('wastage.approve'));
        $app->post('/stock/wastage/{id}/reject', [WastageController::class, 'reject'])->add($need('wastage.approve'));
        $app->get('/stock/new', [StockController::class, 'newForm'])->add($need('items.create'));
        $app->get('/stock/bulk', [StockController::class, 'bulk'])->add($need('stock.view'));
        $app->get('/stock/bulk/new', [StockController::class, 'bulkNew'])->add($need('stock.manageBulkWeights'));
        $app->post('/stock/bulk', [StockController::class, 'bulkSave'])->add($need('stock.manageBulkWeights'));
        $app->get('/stock/bulk/{id}/edit', [StockController::class, 'bulkEdit'])->add($need('stock.manageBulkWeights'));
        $app->post('/stock/bulk/{id}', [StockController::class, 'bulkSave'])->add($need('stock.manageBulkWeights'));
        $app->post('/stock/bulk/{id}/remove', [StockController::class, 'bulkRemove'])->add($need('stock.manageBulkWeights'));
        $app->get('/stock/check', [StockController::class, 'check'])->add($need('stock.view'));
        $app->post('/stock/calc', [StockController::class, 'calc'])->add($need('items.view'));
        $app->post('/stock', [StockController::class, 'create'])->add($need('items.create'));
        $app->get('/stock/{id}', [StockController::class, 'show'])->add($need('items.view'));
        $app->get('/stock/{id}/edit', [StockController::class, 'editForm'])->add($need('items.edit'));
        $app->post('/stock/{id}', [StockController::class, 'update'])->add($need('items.edit'));
        $app->post('/stock/{id}/status', [StockController::class, 'setStatus'])->add($need('items.edit'));
        $app->post('/stock/{id}/remove', [StockController::class, 'remove'])->add($need('items.delete'));

        // Purchases
        $app->get('/purchases', [PurchaseController::class, 'index'])->add($need('purchases.view'));
        $app->get('/purchases/list', [PurchaseController::class, 'list'])->add($need('purchases.view'));
        $app->get('/purchases/new', [PurchaseController::class, 'newForm'])->add($need('purchases.create'));
        $app->post('/purchases/calc', [PurchaseController::class, 'calc'])->add($need('purchases.create'));
        $app->post('/purchases', [PurchaseController::class, 'create'])->add($need('purchases.create'));
        $app->get('/purchases/{id}', [PurchaseController::class, 'show'])->add($need('purchases.view'));
        $app->post('/purchases/{id}/total', [PurchaseController::class, 'total'])->add($need('purchases.edit'));
        $app->post('/purchases/{id}/remove', [PurchaseController::class, 'remove'])->add($need('purchases.delete'));

        // Stock tally
        $app->get('/tally', [TallyController::class, 'index'])->add($need('tally.view'));
        $app->get('/tally/list', [TallyController::class, 'list'])->add($need('tally.view'));
        $app->post('/tally', [TallyController::class, 'start'])->add($need('tally.create'));
        $app->get('/tally/{id}', [TallyController::class, 'show'])->add($need('tally.view'));
        $app->get('/tally/{id}/panel', [TallyController::class, 'panel'])->add($need('tally.view'));
        $app->post('/tally/{id}/scan', [TallyController::class, 'scan'])->add($need('tally.scan'));
        $app->post('/tally/{id}/verify', [TallyController::class, 'verify'])->add($need('tally.scan'));
        $app->get('/tally/{id}/lock', [TallyController::class, 'lockForm'])->add($need('tally.lock'));
        $app->post('/tally/{id}/lock', [TallyController::class, 'lock'])->add($need('tally.lock'));

        // Customers, suppliers, karigars
        $app->get('/directory', [DirectoryController::class, 'index'])->add($need('directory.view'));
        $app->get('/directory/list', [DirectoryController::class, 'list'])->add($need('directory.view'));
        $app->get('/directory/lookup', [DirectoryController::class, 'lookup'])->add($need('directory.view'));
        $app->post('/directory/translate', [DirectoryController::class, 'translate'])->add($need('directory.create'));
        $app->get('/directory/customers/new', [DirectoryController::class, 'newForm'])->add($need('directory.create'));
        $app->post('/directory/customers', [DirectoryController::class, 'create'])->add($need('directory.create'));
        $app->get('/directory/customers/{id}', [DirectoryController::class, 'show'])->add($need('directory.view'));
        $app->get('/directory/customers/{id}/edit', [DirectoryController::class, 'editForm'])->add($need('directory.edit'));
        $app->post('/directory/customers/{id}', [DirectoryController::class, 'update'])->add($need('directory.edit'));
        $app->get('/directory/{kind:suppliers|karigars}/{id}', [DirectoryController::class, 'party'])->add($need('directory.view'));

        // Reports
        $app->get('/reports', [ReportsController::class, 'index'])->add($need('reports.view'));

        // GST Summary
        $app->get('/gst', [GstController::class, 'index'])->add($need('gst.viewReports'));
        $app->get('/gst/export', [GstController::class, 'export'])->add($need('gst.viewReports'));
        $app->get('/gst/filings/new', [GstController::class, 'filingForm'])->add($need('gst.manageFilings'));
        $app->post('/gst/filings', [GstController::class, 'filingSave'])->add($need('gst.manageFilings'));

        // Admin Control
        $app->get('/admin/staff', [AdminStaffController::class, 'index'])->add($need('users.manage'));
        $app->get('/admin/staff/live', [AdminStaffController::class, 'live'])->add($need('users.manage'));
        $app->get('/admin/staff/new', [AdminStaffController::class, 'newForm'])->add($need('users.manage'));
        $app->post('/admin/staff', [AdminStaffController::class, 'create'])->add($need('users.manage'));
        $app->get('/admin/staff/{id}', [AdminStaffController::class, 'show'])->add($need('users.manage'));
        $app->post('/admin/staff/{id}', [AdminStaffController::class, 'update'])->add($need('users.manage'));
        $app->get('/admin/staff/{id}/password', [AdminStaffController::class, 'passwordForm'])->add($need('users.resetPassword'));
        $app->post('/admin/staff/{id}/password', [AdminStaffController::class, 'password'])->add($need('users.resetPassword'));
        $app->post('/admin/staff/{id}/permissions', [AdminStaffController::class, 'permissions'])->add($need('users.manage'));
        $app->post('/admin/staff/{id}/deactivate', [AdminStaffController::class, 'deactivate'])->add($need('users.manage'));
        $app->post('/admin/roles/{role}', [AdminStaffController::class, 'saveRole'])->add($need('users.manage'));
        $app->get('/admin/updates', [AdminController::class, 'updates'])->add($need('appUpdate.manage'));
        $app->post('/admin/updates', [AdminController::class, 'publishUpdate'])->add($need('appUpdate.manage'));
        $app->post('/admin/updates/upload', [AdminController::class, 'uploadApk'])->add($need('appUpdate.manage'));
        $app->post('/admin/updates/publish', [AdminController::class, 'publishApk'])->add($need('appUpdate.manage'));
        $app->post('/admin/updates/discard', [AdminController::class, 'discardApk'])->add($need('appUpdate.manage'));
        $app->post('/admin/updates/maintenance', [AdminController::class, 'updateMaintenance'])->add($need('appUpdate.manage'));
        $app->get('/admin/branches', [AdminBranchController::class, 'index'])->add($need('directory.manageBranches'));
        $app->post('/admin/branches', [AdminBranchController::class, 'create'])->add($need('directory.manageBranches'));
        $app->get('/admin/branches/{id}', [AdminBranchController::class, 'show'])->add($need('directory.manageBranches'));
        $app->post('/admin/branches/{id}', [AdminBranchController::class, 'update'])->add($need('directory.manageBranches'));
        $app->post('/admin/branches/{id}/counters', [AdminBranchController::class, 'counterAdd'])->add($need('directory.manageBranches'));
        $app->post('/admin/branches/{id}/counters/{cid}', [AdminBranchController::class, 'counterSave'])->add($need('directory.manageBranches'));
        $app->post('/admin/branches/{id}/staff/{uid}', [AdminBranchController::class, 'staffAssign'])->add($need('users.manage'));
        $app->post('/admin/branches/{id}/staff', [AdminBranchController::class, 'staffAssign'])->add($need('users.manage'));
        $app->get('/admin/login-screen', [AdminController::class, 'loginScreen'])->add($need('appAssets.manage'));
        $app->post('/admin/login-screen', [AdminController::class, 'loginScreenAdd'])->add($need('appAssets.manage'));
        $app->post('/admin/login-screen/{id}', [AdminController::class, 'loginScreenSave'])->add($need('appAssets.manage'));
        $app->post('/admin/login-screen/{id}/move', [AdminController::class, 'loginScreenMove'])->add($need('appAssets.manage'));
        $app->post('/admin/login-screen/{id}/delete', [AdminController::class, 'loginScreenDelete'])->add($need('appAssets.manage'));
        $app->get('/admin/notifications', [AdminController::class, 'notifications'])->add($need('notifications.send'));
        $app->post('/admin/notifications', [AdminController::class, 'sendNotification'])->add($need('notifications.send'));
        $app->get('/admin/settings', [AdminController::class, 'settings'])->add($need('settings.manageStockRules'));
        $app->post('/admin/settings', [AdminController::class, 'saveSettings'])->add($need('settings.manageStockRules'));
        $app->post('/admin/settings/reset', [AdminController::class, 'resetSettings'])->add($need('settings.manageStockRules'));
        $app->get('/admin/audit', [AdminController::class, 'audit'])->add($need('users.manage'));
        $app->get('/admin/server', [AdminController::class, 'server'])->add($need('users.manage'));
        $app->get('/admin/backup', [BackupController::class, 'index'])->add($need('users.manage'));
        $app->post('/admin/backup/inspect', [BackupController::class, 'inspect'])->add($need('users.manage'));
        $app->post('/admin/backup/download', [BackupController::class, 'download'])->add($need('users.manage'));

        // Old metal
        $app->get('/old-metal', [OldMetalController::class, 'index'])->add($need('oldMetal.view'));
        $app->get('/old-metal/list', [OldMetalController::class, 'list'])->add($need('oldMetal.view'));
        $app->get('/old-metal/new', [OldMetalController::class, 'form'])->add($need('oldMetal.create'));
        $app->post('/old-metal/calc', [OldMetalController::class, 'calc'])->add($need('oldMetal.view'));
        $app->post('/old-metal', [OldMetalController::class, 'create'])->add($need('oldMetal.create'));
        $app->post('/old-metal/{id}/cancel', [OldMetalController::class, 'cancel'])->add($need('oldMetal.create'));

        // menu pages not built yet
        foreach (Nav::forAll() as $it) {
            if (!$it['ready'] && $it['href'] !== '/') {
                $app->get($it['href'], [PageController::class, 'soon'])->add($auth);
            }
        }
        return $app;
    }
}
