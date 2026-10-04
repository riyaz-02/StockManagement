<?php
declare(strict_types=1);

namespace Portal\Support;

use Portal\Auth\Session;
use Portal\Config;
use Twig\Extension\AbstractExtension;
use Twig\Markup;
use Twig\TwigFilter;
use Twig\TwigFunction;

/** Small helpers for the templates: words, money, icons, permission checks, cache-busted asset links. */
final class TwigExtension extends AbstractExtension
{
    /** Simple 24px line icons (stroke). Name => SVG path data. */
    private const ICONS = [
        'home' => 'M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10',
        'download' => 'M12 3v12M7 10l5 5 5-5M4 20h16',
        'receipt' => 'M6 3h12v18l-3-2-3 2-3-2-3 2V3zM9 8h6M9 12h6',
        'quote' => 'M7 3h8l4 4v14H7V3zM14 3v5h5M10 13h6M10 17h6',
        'hammer' => 'M14 6l4 4M4 20l8-8M10 4l6 6-3 3-6-6 3-3zM17 3l4 4-2 2-4-4 2-2z',
        'hourglass' => 'M7 3h10M7 21h10M8 3c0 5 8 5 8 9s-8 4-8 9M16 3c0 5-8 5-8 9',
        'gem' => 'M6 3h12l4 6-10 12L2 9l4-6zM2 9h20M9 3l3 6 3-6M12 21L9 9M12 21l3-12',
        'recycle' => 'M7 19H4l3-5M4 19l4-7M17 5h3l-3 5M20 5l-4 7M12 21a8 8 0 01-6-2.6M12 3a8 8 0 016 2.6M4 12a8 8 0 010-.1',
        'truck' => 'M2 6h11v10H2zM13 9h5l3 3v4h-8zM6 19a2 2 0 100-4 2 2 0 000 4zM17 19a2 2 0 100-4 2 2 0 000 4z',
        'check' => 'M4 12l5 5L20 6',
        'book' => 'M4 4h11a3 3 0 013 3v13H7a3 3 0 01-3-3V4zM8 8h6M8 12h6',
        'wallet' => 'M3 7h16a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V7zM3 7l12-3v3M17 14h2',
        'chart' => 'M4 19V5M4 19h16M8 15l4-4 3 3 5-6',
        'bars' => 'M6 20V10M12 20V4M18 20v-7',
        'users' => 'M9 11a3 3 0 100-6 3 3 0 000 6zM3 20a6 6 0 0112 0M17 11a3 3 0 000-6M21 20a6 6 0 00-4-5.6',
        'shield' => 'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3zM9 12l2 2 4-4',
        'phone' => 'M8 2h8a1 1 0 011 1v18a1 1 0 01-1 1H8a1 1 0 01-1-1V3a1 1 0 011-1zM11 18h2',
        'bell' => 'M6 9a6 6 0 1112 0c0 6 2 7 2 8H4c0-1 2-2 2-8zM10 21h4',
        'sliders' => 'M4 7h9M17 7h3M4 17h3M11 17h9M13 5v4M7 15v4',
        'list' => 'M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01',
        'logout' => 'M9 4H5a1 1 0 00-1 1v14a1 1 0 001 1h4M16 8l4 4-4 4M20 12H9',
        'menu' => 'M4 6h16M4 12h16M4 18h16',
        'x' => 'M6 6l12 12M18 6L6 18',
        'edit' => 'M4 20h4L19 9l-4-4L4 16v4zM14 6l4 4',
        'store' => 'M4 9l1-5h14l1 5M4 9a2 2 0 004 0 2 2 0 004 0 2 2 0 004 0 2 2 0 004 0M5 12v8h14v-8M10 20v-5h4v5',
        'search' => 'M11 19a8 8 0 100-16 8 8 0 000 16zM21 21l-4.3-4.3',
        'plus' => 'M12 5v14M5 12h14',
        'alert' => 'M12 3l10 18H2L12 3zM12 10v5M12 18h.01',
        'refresh' => 'M4 12a8 8 0 0114-5.3L20 9M20 4v5h-5M20 12a8 8 0 01-14 5.3L4 15M4 20v-5h5',
        'server' => 'M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01',
        'scale' => 'M12 3v17M7 20h10M4 7h16M4 7l-2.5 6a3 3 0 005 0L4 7zM20 7l-2.5 6a3 3 0 005 0L20 7z',
    ];

    public function getFunctions(): array
    {
        return [
            new TwigFunction('t', fn (string $k, array $v = []) => I18n::t($k, $v)),
            new TwigFunction('can', fn (string $k) => Session::can($k)),
            new TwigFunction('user', fn () => Session::user()),
            new TwigFunction('is_admin', fn () => Session::isAdmin()),
            new TwigFunction('csrf', fn () => Session::csrf()),
            new TwigFunction('csrf_field', fn () => new Markup('<input type="hidden" name="_csrf" value="' . htmlspecialchars(Session::csrf(), ENT_QUOTES) . '">', 'UTF-8')),
            new TwigFunction('asset', [$this, 'asset']),
            new TwigFunction('icon', [$this, 'icon']),
            new TwigFunction('app_name', fn () => Config::get('PORTAL_APP_NAME', 'Laltu Guinea Palace')),
            new TwigFunction('is_dev', fn () => Config::isDev()),
            new TwigFunction('nav', fn () => Nav::forUser()),
            new TwigFunction('nav_meta', fn (string $key) => Nav::meta($key)),
        ];
    }

    public function getFilters(): array
    {
        return [
            new TwigFilter('inr', fn ($v, int $d = 2) => Money::inr($v, $d)),
            new TwigFilter('grams', fn ($v) => Money::grams($v)),
            new TwigFilter('bytes', fn ($v) => Money::bytes($v)),
            new TwigFilter('dmy', function ($v) {
                $t = is_string($v) ? strtotime(substr($v, 0, 10)) : false;
                return $t ? date('d M Y', $t) : (string) $v;
            }),
            new TwigFilter('dmy_time', function ($v) {
                $t = is_string($v) ? strtotime($v) : false;
                return $t ? date('d M Y, h:i A', $t) : (string) $v;
            }),
            // "just now", "5 min ago", "3 h ago", "yesterday", else the date: for the bell
            new TwigFilter('ago', function ($v) {
                $t = is_string($v) && $v !== '' ? strtotime($v) : false;
                if (!$t) {
                    return '';
                }
                $d = time() - $t;
                return $d < 60 ? 'just now' : ($d < 3600 ? intdiv($d, 60) . ' min ago' : ($d < 86400 ? intdiv($d, 3600) . ' h ago' : ($d < 172800 ? 'yesterday' : date('d M', $t))));
            }),
            new TwigFilter('pretty', fn ($v) => ucfirst(str_replace('_', ' ', (string) $v))),
        ];
    }

    /** /assets/... link with the file's change time, so a new version is never served from an old browser cache. */
    public function asset(string $path): string
    {
        $file = Config::path('public/assets/' . ltrim($path, '/'));
        return '/assets/' . ltrim($path, '/') . (is_file($file) ? '?v=' . filemtime($file) : '');
    }

    public function icon(string $name, int $size = 20): Markup
    {
        $d = self::ICONS[$name] ?? self::ICONS['list'];
        return new Markup(sprintf('<svg class="ico" width="%1$d" height="%1$d" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="%2$s"/></svg>', $size, htmlspecialchars($d, ENT_QUOTES)), 'UTF-8');
    }
}
