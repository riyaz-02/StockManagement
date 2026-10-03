<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiClient;
use Portal\Api\ApiException;
use Portal\Auth\Session;
use Portal\Http\Api;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Views\Twig;

/** Shared helpers for the page controllers: render, call the API, talk to HTMX (toasts, closing the pop-up, refreshing lists). */
abstract class BaseController
{
    protected function view(Request $rq, Response $rs, string $template, array $data = []): Response
    {
        // A message kept for "the next page" (flash() then redirect) is shown once, on the next full page. A background
        // partial (a list refreshing itself) must not swallow it, so only a normal page request takes it.
        if (!array_key_exists('flash', $data) && !$this->isHx($rq)) {
            $data['flash'] = Session::flash();
        }
        return Twig::fromRequest($rq)->render($rs, $template, $data);
    }

    protected function api(): ApiClient
    {
        return Api::client();
    }

    protected function q(Request $rq, string $key, string $default = ''): string
    {
        $v = $rq->getQueryParams()[$key] ?? $default;
        return is_string($v) ? trim($v) : $default;
    }

    /** Parsed form body (POST). */
    protected function input(Request $rq): array
    {
        return (array) $rq->getParsedBody();
    }

    protected function isHx(Request $rq): bool
    {
        return $rq->getHeaderLine('HX-Request') !== '';
    }

    protected function flash(string $type, string $text): void
    {
        Session::flash(['type' => $type, 'text' => $text]);
    }

    protected function redirect(Response $rs, string $to): Response
    {
        return $rs->withHeader('Location', $to)->withStatus(302);
    }

    /** HTMX: tell the browser things happened (events) without sending a page. */
    protected function trigger(Response $rs, array $events, int $status = 204): Response
    {
        return $rs->withStatus($status)->withHeader('HX-Trigger', json_encode($events, JSON_UNESCAPED_UNICODE));
    }

    /** A saved pop-up form: close it, show a message, refresh the lists behind it. */
    protected function done(Response $rs, string $text, array $more = []): Response
    {
        return $this->trigger($rs, ['toast' => ['type' => 'success', 'text' => $text], 'modal-close' => true, 'data-changed' => true] + $more);
    }

    /** After an action on a detail page: show a message and reload the page (HTMX does the reload). */
    protected function refreshWith(Response $rs, string $type, string $text): Response
    {
        $this->flash($type, $text);
        return $rs->withStatus(204)->withHeader('HX-Refresh', 'true');
    }

    protected function toast(Response $rs, string $type, string $text, int $status = 204): Response
    {
        return $this->trigger($rs, ['toast' => ['type' => $type, 'text' => $text]], $status);
    }

    /** New unique id for "this exact request": the API then never makes a duplicate if a form is sent twice. */
    protected function requestId(string $prefix): string
    {
        return $prefix . '-' . bin2hex(random_bytes(10));
    }

    /** Errors that the whole page must handle (asleep, signed out) are rethrown; the rest are shown next to the form. */
    protected function rethrowIfSystem(ApiException $e): void
    {
        if ($e->unauthorized() || $e->down()) {
            throw $e;
        }
    }

    /** @return array{from:string,to:string,quick:string} a date range from ?quick=today|yesterday|month or ?from&to */
    protected function range(Request $rq): array
    {
        $today = date('Y-m-d');
        $from = $this->q($rq, 'from');
        $to = $this->q($rq, 'to');
        $quick = $this->q($rq, 'quick');
        $ok = fn (string $d) => preg_match('/^\d{4}-\d{2}-\d{2}$/', $d) === 1;
        if ($quick === 'yesterday') {
            $from = $to = date('Y-m-d', strtotime('-1 day'));
        } elseif ($quick === 'month') {
            $from = date('Y-m-01');
            $to = $today;
        } elseif ($quick === 'today') {
            $from = $to = $today;
        } elseif ($ok($from)) {
            $to = $ok($to) ? $to : $from;
            $quick = 'custom';
        } else {
            $from = $to = $today;
            $quick = 'today';
        }
        if ($from > $to) {
            [$from, $to] = [$to, $from];
        }
        return ['from' => $from, 'to' => $to, 'quick' => $quick];
    }
}
