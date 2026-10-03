<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** The owner's daily page: money in and out by payment mode, what happened, every entry. */
final class DayBookController extends BaseController
{
    public function index(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'daybook/index.twig', ['active' => 'daybook', 'range' => $this->range($rq)]);
    }

    public function body(Request $rq, Response $rs): Response
    {
        $range = $this->range($rq);
        $d = $this->api()->get('billing/daybook', ['from' => $range['from'], 'to' => $range['to']])['data'] ?? [];
        $modes = (array) ($d['modes'] ?? []);
        $cash = 0.0;
        foreach ($modes as $m) {
            if (($m['mode'] ?? '') === 'Cash') {
                $cash = (float) ($m['net'] ?? 0);
            }
        }
        return $this->view($rq, $rs, 'daybook/body.twig', ['d' => $d, 'cash' => $cash, 'range' => $range]);
    }
}
