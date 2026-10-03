<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** Stock tally: start one, scan every piece (a barcode scanner types into the box), see what is left box by box, lock it. */
final class TallyController extends BaseController
{
    private const LOCKED = ['locked', 'force_locked'];

    public function index(Request $rq, Response $rs): Response
    {
        return $this->view($rq, $rs, 'tally/index.twig', ['active' => 'tally']);
    }

    public function list(Request $rq, Response $rs): Response
    {
        $sessions = (array) ($this->api()->get('tally')['data']['tallySessions'] ?? []);
        $running = null;
        $past = [];
        foreach ($sessions as $s) {
            if (($s['status'] ?? '') === 'active' && $running === null) {
                $running = $s;
            } else {
                $past[] = $s;
            }
        }
        $preview = null;
        if ($running === null) {
            try {
                $preview = $this->api()->get('tally/preview')['data'] ?? null;
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        return $this->view($rq, $rs, 'tally/list.twig', ['running' => $running, 'past' => $past, 'preview' => $preview]);
    }

    public function start(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        try {
            $r = $this->api()->post('tally', ['description' => (string) ($b['description'] ?? '')]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->toast($rs, 'error', $e->getMessage());
        }
        return $rs->withStatus(204)->withHeader('HX-Redirect', '/tally/' . rawurlencode((string) ($r['data']['tallySession']['_id'] ?? '')));
    }

    public function show(Request $rq, Response $rs, array $args): Response
    {
        $s = $this->api()->get('tally/' . rawurlencode($args['id']))['data']['tallySession'] ?? [];
        return $this->view($rq, $rs, 'tally/show.twig', ['s' => $s, 'locked' => in_array($s['status'] ?? '', self::LOCKED, true), 'active' => 'tally']);
    }

    /** Progress, the boxes still to check, and what is left to find: refreshed after every scan. */
    public function panel(Request $rq, Response $rs, array $args): Response
    {
        $id = rawurlencode($args['id']);
        $s = $this->api()->get("tally/$id")['data']['tallySession'] ?? [];
        $sum = $this->api()->get("tally/$id/summary")['data'] ?? [];
        return $this->view($rq, $rs, 'tally/panel.twig', ['s' => $s, 'sum' => $sum, 'locked' => in_array($s['status'] ?? '', self::LOCKED, true)]);
    }

    public function scan(Request $rq, Response $rs, array $args): Response
    {
        $code = trim((string) ($this->input($rq)['barcode'] ?? ''));
        if ($code === '') {
            return $this->view($rq, $rs, 'tally/result.twig', ['r' => null]);
        }
        try {
            $r = $this->api()->put('tally/' . rawurlencode($args['id']) . '/scan', ['barcode' => $code]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->view($rq, $rs, 'tally/result.twig', ['r' => ['error' => $e->getMessage(), 'code' => $code]]);
        }
        $d = $r['data'] ?? [];
        if (!empty($r['requiresWeightVerification'])) {
            return $this->view($rq, $rs, 'tally/result.twig', ['r' => ['verify' => $d['item'] ?? [], 'id' => $args['id']]]);
        }
        return $this->view($rq, $rs, 'tally/result.twig', ['r' => ['ok' => $d['item'] ?? [], 'msg' => (string) ($r['message'] ?? ''), 'out' => !empty($d['isOutOfStock']), 'count' => $d['scannedCount'] ?? 0, 'of' => $d['expectedCount'] ?? 0]])
            ->withHeader('HX-Trigger', json_encode(['tally-scanned' => true]));
    }

    public function verify(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        try {
            $r = $this->api()->put('tally/' . rawurlencode($args['id']) . '/verify-weight', ['itemId' => (string) ($b['itemId'] ?? ''), 'verifiedWeight' => (float) ($b['verifiedWeight'] ?? 0)]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->view($rq, $rs, 'tally/result.twig', ['r' => ['error' => $e->getMessage(), 'code' => (string) ($b['barcode'] ?? '')]]);
        }
        $d = $r['data'] ?? [];
        return $this->view($rq, $rs, 'tally/result.twig', ['r' => ['ok' => $d['item'] ?? [], 'msg' => 'Weight checked', 'out' => false, 'count' => $d['scannedCount'] ?? 0, 'of' => $d['expectedCount'] ?? 0]])
            ->withHeader('HX-Trigger', json_encode(['tally-scanned' => true]));
    }

    public function lockForm(Request $rq, Response $rs, array $args): Response
    {
        $sum = $this->api()->get('tally/' . rawurlencode($args['id']) . '/summary')['data'] ?? [];
        return $this->view($rq, $rs, 'tally/lock.twig', ['id' => $args['id'], 'sum' => $sum, 'error' => null]);
    }

    public function lock(Request $rq, Response $rs, array $args): Response
    {
        $b = $this->input($rq);
        try {
            $this->api()->put('tally/' . rawurlencode($args['id']) . '/lock', ['remarks' => (string) ($b['remarks'] ?? '')]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $sum = $this->api()->get('tally/' . rawurlencode($args['id']) . '/summary')['data'] ?? [];
            return $this->view($rq, $rs->withStatus(422), 'tally/lock.twig', ['id' => $args['id'], 'sum' => $sum, 'error' => $e->getMessage(), 'v' => $b]);
        }
        return $this->refreshWith($rs, 'success', 'Tally locked');
    }
}
