<?php
declare(strict_types=1);

/**
 * Runs every portal test in turn:  php tests/all.php
 * Needs the portal (http://localhost:8080) and the DEV API (http://localhost:5000) running. Never run against production.
 */
$suites = ['run.php', 'smoke.php', 'pages.php', 'billing.php', 'stock.php', 'purchases.php', 'tally.php', 'directory.php', 'gst.php', 'admin.php', 'backup.php', 'summary.php'];
$bad = 0;
foreach ($suites as $s) {
    echo "\n===== $s =====\n";
    passthru('php ' . escapeshellarg(__DIR__ . '/' . $s), $code);
    $bad += $code === 0 ? 0 : 1;
}
echo "\n" . ($bad === 0 ? 'ALL SUITES PASSED' : "$bad suite(s) FAILED") . "\n";
exit($bad === 0 ? 0 : 1);

