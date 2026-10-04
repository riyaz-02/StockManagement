<?php
declare(strict_types=1);

namespace Portal\Http\Middleware;

use Portal\Config;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface as Handler;

/** Browser-side protection on every page: no framing, no sniffing, scripts only from this site, no leaking of the address. */
final class SecurityHeaders implements MiddlewareInterface
{
    public function process(Request $request, Handler $handler): Response
    {
        $r = $handler->handle($request);
        // pictures may come from Cloudinary (the old ones) and from the shop's S3 bucket / CloudFront address (the new ones)
        $imgHosts = trim('https://res.cloudinary.com https://*.s3.ap-south-1.amazonaws.com ' . (string) Config::get('PORTAL_IMG_HOSTS', ''));
        $csp = "default-src 'self'; img-src 'self' data: " . $imgHosts . "; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self' " . Config::publicApiBase() . "; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
        $r = $r->withHeader('Content-Security-Policy', $csp)
            ->withHeader('X-Frame-Options', 'DENY')
            ->withHeader('X-Content-Type-Options', 'nosniff')
            ->withHeader('Referrer-Policy', 'same-origin')
            ->withHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()')
            ->withHeader('Cache-Control', 'no-store');
        if (!Config::isDev()) {
            $r = $r->withHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
        }
        return $r;
    }
}
