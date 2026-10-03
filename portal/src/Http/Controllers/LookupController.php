<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

/** The list under a customer search box: saved customers that match, plus "use this name as a new customer". */
final class LookupController extends BaseController
{
    public function customers(Request $rq, Response $rs): Response
    {
        $q = $this->q($rq, 'customerName', $this->q($rq, 'q'));
        $rows = [];
        if (mb_strlen($q) >= 2) {
            try {
                $rows = (array) ($this->api()->get('directory/customers/lookup', ['q' => $q])['data'] ?? []);
            } catch (ApiException $e) {
                $this->rethrowIfSystem($e);
            }
        }
        return $this->view($rq, $rs, 'lookup/customers.twig', ['rows' => $rows, 'q' => $q]);
    }
}
