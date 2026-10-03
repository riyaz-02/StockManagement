<?php
declare(strict_types=1);

// Never show a raw PHP error to a visitor, even one that happens before our own error page can take over (a bad
// .env, a missing extension...). Everything is still logged. Slim's own debug page (dev only, see App.php) is a
// separate mechanism and is unaffected by this.
error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('display_startup_errors', '0');

// Front door of the portal: every page request comes here.
require __DIR__ . '/../vendor/autoload.php';

Portal\App::create(dirname(__DIR__))->run();
