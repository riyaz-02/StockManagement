<?php
declare(strict_types=1);

namespace Portal\Http;

use Portal\Api\ApiClient;
use Portal\Auth\Session;

/** The API client for the person who is signed in (their token, their chosen branch). */
final class Api
{
    public static function client(): ApiClient
    {
        return new ApiClient(Session::token(), Session::branch());
    }
}
