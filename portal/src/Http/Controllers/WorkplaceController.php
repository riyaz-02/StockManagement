<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiClient;
use Portal\Api\ApiException;
use Portal\Auth\Session;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/**
 * "Working at": the branch (for people who may switch) and the billing counter, kept for the session and sent with every call
 * (X-Branch, X-Counter). The API decides what is allowed; this only remembers the choice and shows the lists.
 */
final class WorkplaceController extends BaseController
{
    private function maySwitchBranch(): bool
    {
        return Session::isAdmin() || Session::can('branches.viewAll') || Session::can('billing.viewAllBranches');
    }

    /** The two little drop-downs in the top bar. */
    public function show(Request $rq, Response $rs): Response
    {
        $branches = [];
        $cur = ['branchId' => 'main', 'counters' => [], 'selectedId' => '', 'assignedId' => ''];
        try {
            if ($this->maySwitchBranch()) {
                // asked without the branch choice, so the whole list is there to choose from (not just the branch already chosen)
                $branches = (array) ((new ApiClient(Session::token()))->get('branches', [], 10)['data']['branches'] ?? []);
            }
            $cur = (array) ($this->api()->get('branches/counters/current', [], 10)['data'] ?? []) + $cur;
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        $branches = array_values(array_filter($branches, fn ($b) => ($b['isActive'] ?? true) !== false));
        return $this->view($rq, $rs, 'partials/workplace.twig', [
            'branches' => $this->maySwitchBranch() && count($branches) > 1 ? $branches : [],
            'branchSel' => Session::branch(),
            'counters' => (array) $cur['counters'],
            'counterSel' => Session::counter() !== '' ? Session::counter() : (string) ($cur['selectedId'] ?? ''),
            'flash' => null,
        ]);
    }

    /** A choice was made: remember it and have the page reload so every list follows it. */
    public function save(Request $rq, Response $rs): Response
    {
        $b = $this->input($rq);
        if (array_key_exists('branch', $b) && $this->maySwitchBranch()) {
            $new = (string) $b['branch'];
            if ($new !== Session::branch()) {
                Session::setBranch(preg_match('/^(main|all|[a-f0-9]{24})$/', $new) ? $new : '');
                Session::setCounter('');   // a counter belongs to one branch
            }
        }
        if (array_key_exists('counter', $b)) {
            $c = (string) $b['counter'];
            Session::setCounter(preg_match('/^[a-f0-9]{24}$/', $c) ? $c : '');
        }
        return $rs->withStatus(204)->withHeader('HX-Refresh', 'true');
    }
}
