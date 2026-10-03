<?php
// Router for PHP's built-in server (development):  php -S localhost:8080 -t public router.php
// Real files (css, js, images) are served as they are; everything else goes to index.php.
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
$file = __DIR__ . '/public' . $path;
if ($path !== '/' && is_file($file)) {
    return false;
}
require __DIR__ . '/public/index.php';
