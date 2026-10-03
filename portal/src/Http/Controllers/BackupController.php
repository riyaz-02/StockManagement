<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiException;
use Portal\Auth\Session;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Psr7\Response as SlimResponse;

/**
 * Admin Control > Data backup: paste a MongoDB connection string, see what is in it, download all of it as one file.
 * The address (it holds a password) is only ever passed on to the API for that one request: never stored, never shown again.
 * Admin / Owner only (the API enforces it too).
 */
final class BackupController extends BaseController
{
    public function index(Request $rq, Response $rs): Response
    {
        if ($blocked = $this->adminOnly()) {
            return $blocked;
        }
        $history = [];
        try {
            $history = (array) ($this->api()->get('admin/audit', ['entity' => 'backup', 'limit' => 5])['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
        }
        return $this->view($rq, $rs, 'admin/backup.twig', ['history' => $history, 'active' => 'backup']);
    }

    /** "Check connection": what databases and collections are there (HTMX fills the result block). */
    public function inspect(Request $rq, Response $rs): Response
    {
        if ($blocked = $this->adminOnly()) {
            return $blocked;
        }
        $b = $this->input($rq);
        try {
            $d = (array) ($this->api()->post('admin/backup/inspect', ['uri' => trim((string) ($b['uri'] ?? ''))], 60)['data'] ?? []);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            return $this->view($rq, $rs->withStatus(422), 'admin/backup_result.twig', ['error' => $e->getMessage(), 'd' => null]);
        }
        return $this->view($rq, $rs, 'admin/backup_result.twig', ['error' => null, 'd' => $d]);
    }

    /** "Download backup": the file is streamed straight through; a refusal before the first byte comes back as a message on the page. */
    public function download(Request $rq, Response $rs): Response
    {
        if ($blocked = $this->adminOnly()) {
            return $blocked;
        }
        $b = $this->input($rq);
        $databases = array_values(array_filter(array_map('strval', (array) ($b['db'] ?? [])), fn ($n) => $n !== ''));
        if (!$databases) {
            $this->flash('error', 'Tick at least one database to copy, then download.');
            return $this->redirect($rs, '/admin/backup');
        }
        try {
            $this->api()->download('admin/backup/download', [
                'uri' => trim((string) ($b['uri'] ?? '')), 'databases' => $databases, 'includeReadable' => !empty($b['readable']),
            ]);
        } catch (ApiException $e) {
            $this->rethrowIfSystem($e);
            $this->flash('error', $e->getMessage());
            return $this->redirect($rs, '/admin/backup');
        }
        exit;   // the file has already been sent to the browser; there is no page to add to it
    }

    private function adminOnly(): ?Response
    {
        if (Session::isAdmin()) {
            return null;
        }
        $r = new SlimResponse(403);
        $r->getBody()->write('Only the Admin or Owner can make a data backup.');
        return $r;
    }
}
