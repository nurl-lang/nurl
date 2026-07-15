// http_extras.nu — Phase 7 acceptance test for stdlib/ext/http_static.nu
// + stdlib/ext/http_auth.nu. Pure offline: no socket, no filesystem
// reads. Covers MIME lookup, Authorization parsers, cookie parser,
// and Set-Cookie serialiser.
//
// Coverage:
//   * mime_for_ext: html, css, js, json, png, jpg, jpeg, svg, woff2,
//     wasm, pdf, csv, unknown → application/octet-stream, empty, mixed
//     case extensions.
//   * parse_basic_auth: valid `user:pass`, embedded `:` in pass, missing
//     header, wrong scheme, malformed base64, missing colon in decoded.
//   * parse_bearer_auth: valid token, missing header, wrong scheme,
//     surrounding whitespace, empty token.
//   * request_cookie: single cookie, multiple cookies, missing cookie,
//     missing header, leading/trailing whitespace.
//   * response_set_cookie: name+value, full-options serialization
//     (Path, Domain, Max-Age, Secure, HttpOnly, SameSite=Strict).
//   * _has_dotdot_segment: hits `..` at start / middle / end / mixed
//     separators / nothing-fishy.

$ `stdlib/ext/http_static.nu`
$ `stdlib/ext/http_auth.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http.nu`

@ println_str s prefix s value → v {
    ( nurl_print prefix )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ println_bool s prefix b v → v {
    ( nurl_print prefix )
    ? v { ( nurl_print `T` ) } { ( nurl_print `F` ) }
    ( nurl_print `\n` )
}

@ make_req_with_header s name s value → HttpRequest {
    : HttpRequest req ( request_new )
    ( string_push_str . req method `GET` )
    ( string_push_str . req path `/` )
    ( vec_push [Header] . req headers ( header_new name value ) )
    ^ req
}

// ── mime_for_ext ─────────────────────────────────────────────────────

@ run_mime → v {
    ( nurl_print `── mime_for_ext ──\n` )
    ( println_str `  html  → ` ( mime_for_ext `html` ) )
    ( println_str `  HTML  → ` ( mime_for_ext `HTML` ) )
    ( println_str `  css   → ` ( mime_for_ext `css` ) )
    ( println_str `  js    → ` ( mime_for_ext `js` ) )
    ( println_str `  json  → ` ( mime_for_ext `json` ) )
    ( println_str `  png   → ` ( mime_for_ext `png` ) )
    ( println_str `  jpg   → ` ( mime_for_ext `jpg` ) )
    ( println_str `  jpeg  → ` ( mime_for_ext `jpeg` ) )
    ( println_str `  svg   → ` ( mime_for_ext `svg` ) )
    ( println_str `  woff2 → ` ( mime_for_ext `woff2` ) )
    ( println_str `  wasm  → ` ( mime_for_ext `wasm` ) )
    ( println_str `  pdf   → ` ( mime_for_ext `pdf` ) )
    ( println_str `  csv   → ` ( mime_for_ext `csv` ) )
    ( println_str `  xyz   → ` ( mime_for_ext `xyz` ) )
    ( println_str `  empty → ` ( mime_for_ext `` ) )
}

// ── parse_basic_auth ─────────────────────────────────────────────────

@ run_basic → v {
    ( nurl_print `── parse_basic_auth ──\n` )
    // "alice:secret" base64 = "YWxpY2U6c2VjcmV0"
    : HttpRequest r1 ( make_req_with_header `Authorization` `Basic YWxpY2U6c2VjcmV0` )
    : ?BasicAuth ba1 ( parse_basic_auth r1 )
    ?? ba1 {
        T ok → {
            ( println_str `  user=` ( string_data . ok user ) )
            ( println_str `  pass=` ( string_data . ok pass ) )
            ( basic_auth_free ok )
        }
        F miss → {
            ( nurl_print `  decode FAILED\n` )
            ( basic_auth_free miss )
        }
    }
    ( request_free r1 )

    // "bob:p:wd" (password with embedded ':') base64 = "Ym9iOnA6d2Q="
    : HttpRequest r2 ( make_req_with_header `Authorization` `Basic Ym9iOnA6d2Q=` )
    : ?BasicAuth ba2 ( parse_basic_auth r2 )
    ?? ba2 {
        T ok → {
            ( println_str `  user2=` ( string_data . ok user ) )
            ( println_str `  pass2=` ( string_data . ok pass ) )
            ( basic_auth_free ok )
        }
        F miss → {
            ( nurl_print `  decode2 FAILED\n` )
            ( basic_auth_free miss )
        }
    }
    ( request_free r2 )

    // Missing Authorization header.
    : HttpRequest r3 ( request_new )
    ( string_push_str . r3 method `GET` )
    ( string_push_str . r3 path `/` )
    : ?BasicAuth ba3 ( parse_basic_auth r3 )
    ?? ba3 {
        T ok → { ( nurl_print `  noheader UNEXPECTED Some\n` ) ( basic_auth_free ok ) }
        F miss → { ( nurl_print `  noheader = None\n` ) ( basic_auth_free miss ) }
    }
    ( request_free r3 )

    // Wrong scheme.
    : HttpRequest r4 ( make_req_with_header `Authorization` `Bearer YWxpY2U6c2VjcmV0` )
    : ?BasicAuth ba4 ( parse_basic_auth r4 )
    ?? ba4 {
        T ok → { ( nurl_print `  wrongscheme UNEXPECTED Some\n` ) ( basic_auth_free ok ) }
        F miss → { ( nurl_print `  wrongscheme = None\n` ) ( basic_auth_free miss ) }
    }
    ( request_free r4 )

    // Malformed base64.
    : HttpRequest r5 ( make_req_with_header `Authorization` `Basic !!notbase64!!` )
    : ?BasicAuth ba5 ( parse_basic_auth r5 )
    ?? ba5 {
        T ok → { ( nurl_print `  badb64 UNEXPECTED Some\n` ) ( basic_auth_free ok ) }
        F miss → { ( nurl_print `  badb64 = None\n` ) ( basic_auth_free miss ) }
    }
    ( request_free r5 )

    // Decoded but no ':' separator. "noColon" base64 = "bm9Db2xvbg=="
    : HttpRequest r6 ( make_req_with_header `Authorization` `Basic bm9Db2xvbg==` )
    : ?BasicAuth ba6 ( parse_basic_auth r6 )
    ?? ba6 {
        T ok → { ( nurl_print `  nocolon UNEXPECTED Some\n` ) ( basic_auth_free ok ) }
        F miss → { ( nurl_print `  nocolon = None\n` ) ( basic_auth_free miss ) }
    }
    ( request_free r6 )
}

// ── parse_bearer_auth ────────────────────────────────────────────────

@ run_bearer → v {
    ( nurl_print `── parse_bearer_auth ──\n` )
    : HttpRequest r1 ( make_req_with_header `Authorization` `Bearer abc.def.ghi` )
    : ?String t1 ( parse_bearer_auth r1 )
    ?? t1 {
        T tok → { ( println_str `  token=` ( string_data tok ) ) ( string_free tok ) }
        F e → { ( nurl_print `  bearer UNEXPECTED None\n` ) ( string_free e ) }
    }
    ( request_free r1 )

    // Surrounding whitespace.
    : HttpRequest r2 ( make_req_with_header `Authorization` `Bearer   xyz123  ` )
    : ?String t2 ( parse_bearer_auth r2 )
    ?? t2 {
        T tok → { ( println_str `  trimmed=` ( string_data tok ) ) ( string_free tok ) }
        F e → { ( nurl_print `  trimmed UNEXPECTED None\n` ) ( string_free e ) }
    }
    ( request_free r2 )

    // Empty token.
    : HttpRequest r3 ( make_req_with_header `Authorization` `Bearer ` )
    : ?String t3 ( parse_bearer_auth r3 )
    ?? t3 {
        T tok → { ( println_str `  empty UNEXPECTED Some=` ( string_data tok ) ) ( string_free tok ) }
        F e → { ( nurl_print `  empty = None\n` ) ( string_free e ) }
    }
    ( request_free r3 )

    // Wrong scheme.
    : HttpRequest r4 ( make_req_with_header `Authorization` `Basic YWJj` )
    : ?String t4 ( parse_bearer_auth r4 )
    ?? t4 {
        T tok → { ( println_str `  wrong UNEXPECTED Some=` ( string_data tok ) ) ( string_free tok ) }
        F e → { ( nurl_print `  wrong = None\n` ) ( string_free e ) }
    }
    ( request_free r4 )

    // Missing header.
    : HttpRequest r5 ( request_new )
    ( string_push_str . r5 method `GET` )
    ( string_push_str . r5 path `/` )
    : ?String t5 ( parse_bearer_auth r5 )
    ?? t5 {
        T tok → { ( println_str `  missing UNEXPECTED Some=` ( string_data tok ) ) ( string_free tok ) }
        F e → { ( nurl_print `  missing = None\n` ) ( string_free e ) }
    }
    ( request_free r5 )
}

// ── request_cookie ───────────────────────────────────────────────────

@ run_cookie_get → v {
    ( nurl_print `── request_cookie ──\n` )
    : HttpRequest r1 ( make_req_with_header `Cookie` `session=abc123` )
    : ?String c1 ( request_cookie r1 `session` )
    ?? c1 {
        T v → { ( println_str `  session=` ( string_data v ) ) ( string_free v ) }
        F e → { ( nurl_print `  session UNEXPECTED None\n` ) ( string_free e ) }
    }
    ( request_free r1 )

    : HttpRequest r2 ( make_req_with_header `Cookie` `theme=dark; user=alice; lang=fi` )
    : ?String c2a ( request_cookie r2 `theme` )
    ?? c2a {
        T v → { ( println_str `  theme=` ( string_data v ) ) ( string_free v ) }
        F e → { ( nurl_print `  theme UNEXPECTED None\n` ) ( string_free e ) }
    }
    : ?String c2b ( request_cookie r2 `user` )
    ?? c2b {
        T v → { ( println_str `  user=` ( string_data v ) ) ( string_free v ) }
        F e → { ( nurl_print `  user UNEXPECTED None\n` ) ( string_free e ) }
    }
    : ?String c2c ( request_cookie r2 `lang` )
    ?? c2c {
        T v → { ( println_str `  lang=` ( string_data v ) ) ( string_free v ) }
        F e → { ( nurl_print `  lang UNEXPECTED None\n` ) ( string_free e ) }
    }
    // Missing cookie name.
    : ?String c2d ( request_cookie r2 `missing` )
    ?? c2d {
        T v → { ( println_str `  missing UNEXPECTED Some=` ( string_data v ) ) ( string_free v ) }
        F e → { ( nurl_print `  missing = None\n` ) ( string_free e ) }
    }
    ( request_free r2 )

    // Missing Cookie header.
    : HttpRequest r3 ( request_new )
    ( string_push_str . r3 method `GET` )
    ( string_push_str . r3 path `/` )
    : ?String c3 ( request_cookie r3 `session` )
    ?? c3 {
        T v → { ( println_str `  noheader UNEXPECTED Some=` ( string_data v ) ) ( string_free v ) }
        F e → { ( nurl_print `  noheader = None\n` ) ( string_free e ) }
    }
    ( request_free r3 )
}

// ── response_set_cookie ──────────────────────────────────────────────

@ body_to_string HttpResponse r → String {
    : i n ( vec_len [u] . r body )
    : *u data ( vec_data [u] . r body )
    : String out ( string_with_cap n )
    : ~ i k 0
    ~ < k n {
        : u byte . data k
        ( string_push_char out # i byte )
        = k + k 1
    }
    ^ out
}

@ wire_to_string ( Vec u ) wire → String {
    : i n ( vec_len [u] wire )
    : *u data ( vec_data [u] wire )
    : String out ( string_with_cap n )
    : ~ i k 0
    ~ < k n {
        : u byte . data k
        ( string_push_char out # i byte )
        = k + k 1
    }
    ^ out
}

@ run_cookie_set → v {
    ( nurl_print `── response_set_cookie ──\n` )

    // Plain cookie.
    : HttpResponse a ( response_new 200 )
    : CookieOpts opts1 ( cookie_opts_default )
    ( response_set_cookie a `session` `xyz` opts1 )
    : ( Vec u ) wa ( response_serialize a )
    : String sa ( wire_to_string wa )
    ( println_str `  plain wire:\n` ( string_data sa ) )
    ( string_free sa )
    ( vec_free [u] wa )
    ( http_response_free a )

    // Full options.
    : HttpResponse b ( response_new 200 )
    : CookieOpts opts2 @ CookieOpts {
        `/admin`
        `example.com`
        3600
        T
        T
        @ SameSite { SameSiteStrict }
    }
    ( response_set_cookie b `auth` `tok123` opts2 )
    : ( Vec u ) wb ( response_serialize b )
    : String sb ( wire_to_string wb )
    ( println_str `  full wire:\n` ( string_data sb ) )
    ( string_free sb )
    ( vec_free [u] wb )
    ( http_response_free b )

    // SameSite=Lax + Max-Age=0 (delete-on-receive convention).
    : HttpResponse c ( response_new 200 )
    : CookieOpts opts3 @ CookieOpts {
        `/`
        ``
        0
        F
        F
        @ SameSite { SameSiteLax }
    }
    ( response_set_cookie c `prefs` `light` opts3 )
    : ( Vec u ) wc ( response_serialize c )
    : String sc ( wire_to_string wc )
    ( println_str `  delete wire:\n` ( string_data sc ) )
    ( string_free sc )
    ( vec_free [u] wc )
    ( http_response_free c )
}

// ── _has_dotdot_segment (path traversal) ────────────────────────────

@ run_dotdot → v {
    ( nurl_print `── _has_dotdot_segment ──\n` )
    ( println_bool `  /a/b/c        = ` ( _has_dotdot_segment `/a/b/c` ) )
    ( println_bool `  /a/../b       = ` ( _has_dotdot_segment `/a/../b` ) )
    ( println_bool `  /../etc       = ` ( _has_dotdot_segment `/../etc` ) )
    ( println_bool `  /a/b/..       = ` ( _has_dotdot_segment `/a/b/..` ) )
    ( println_bool `  /a/.b/c       = ` ( _has_dotdot_segment `/a/.b/c` ) )  // dotfile, not ..
    ( println_bool `  /a/...//b     = ` ( _has_dotdot_segment `/a/...//b` ) )  // 3 dots, not ..
    ( println_bool `  /a\\..\\b     = ` ( _has_dotdot_segment `/a\\..\\b` ) )  // backslash sep
    ( println_bool `  ..            = ` ( _has_dotdot_segment `..` ) )
    ( println_bool `  /             = ` ( _has_dotdot_segment `/` ) )
    ( println_bool `  /favicon.ico  = ` ( _has_dotdot_segment `/favicon.ico` ) )
}

// ── main ─────────────────────────────────────────────────────────────

@ main → i {
    ( run_mime )
    ( run_basic )
    ( run_bearer )
    ( run_cookie_get )
    ( run_cookie_set )
    ( run_dotdot )
    ^ 0
}
