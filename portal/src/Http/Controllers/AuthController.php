<?php
declare(strict_types=1);

namespace Portal\Http\Controllers;

use Portal\Api\ApiClient;
use Portal\Api\ApiException;
use Portal\Auth\Session;
use Portal\Auth\Throttle;
use Portal\Support\I18n;
use Portal\Support\LoginSlides;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Views\Twig;

final class AuthController
{
    public function showLogin(Request $request, Response $response): Response
    {
        if (Session::check()) {
            return $response->withHeader('Location', '/')->withStatus(302);
        }
        // the server may be asleep: get it going first, so the login itself is instant
        if (ApiClient::health(3) !== 'online') {
            return $response->withHeader('Location', '/wake?next=' . rawurlencode('/login'))->withStatus(302);
        }
        return Twig::fromRequest($request)->render($response, 'login.twig', ['flash' => Session::flash(), 'mobile' => '', 'slides' => LoginSlides::all()]);
    }

    public function login(Request $request, Response $response): Response
    {
        $view = Twig::fromRequest($request);
        $b = (array) $request->getParsedBody();
        // the same people sign in on the website with a username or an e-mail: anything with a letter or an @ is taken as that,
        // anything that is only digits (and + - spaces) is a mobile number
        $typed = trim((string) ($b['mobile'] ?? ''));
        $isNumber = $typed !== '' && preg_match('/^[\d\s+().-]+$/', $typed) === 1;
        $mobile = $isNumber ? preg_replace('/\D+/', '', $typed) : $typed;
        $password = (string) ($b['password'] ?? '');
        $fail = fn (string $msg, int $code = 200) => $view->render($response->withStatus($code), 'login.twig', ['flash' => ['type' => 'error', 'text' => $msg], 'mobile' => $typed, 'slides' => LoginSlides::all()]);

        if ($typed === '' || ($isNumber && strlen($mobile) < 10) || $password === '') {
            return $fail(I18n::t('login.missing'));
        }
        if ($isNumber) {
            $mobile = substr($mobile, -10);
        }
        $key = ($request->getServerParams()['REMOTE_ADDR'] ?? '') . '|' . strtolower($mobile);
        if (($w = Throttle::wait($key)) > 0) {
            return $fail(I18n::t('login.wait', ['min' => (int) ceil($w / 60)]), 429);
        }

        $api = new ApiClient();
        try {
            $res = $api->post('auth/login', ['mobile' => $mobile, 'password' => $password], 20);
            $token = (string) ($res['data']['token'] ?? '');
            $user = (array) ($res['data']['user'] ?? []);
            if ($token === '' || !$user) {
                throw new ApiException('Unexpected login answer', 502);
            }
            $me = $api->withToken($token)->get('permissions/me');
        } catch (ApiException $e) {
            if ($e->down()) {
                return $response->withHeader('Location', '/wake?next=' . rawurlencode('/login'))->withStatus(302);
            }
            if ($e->unauthorized() || $e->status === 400) {
                Throttle::fail($key);
                return $fail(I18n::t('login.wrong'));
            }
            if ($e->status === 429) {
                return $fail(I18n::t('login.wait', ['min' => 15]), 429);
            }
            return $fail($e->getMessage());
        }
        Throttle::clear($key);
        Session::login($user, $token, (array) ($me['data']['permissions'] ?? []), ($me['data']['all'] ?? false) === true);
        $to = Session::intended();
        return $response->withHeader('Location', $to && str_starts_with($to, '/') && !str_starts_with($to, '//') ? $to : '/')->withStatus(302);
    }

    public function logout(Request $request, Response $response): Response
    {
        Session::logout();
        return $response->withHeader('Location', '/login')->withStatus(302);
    }
}
