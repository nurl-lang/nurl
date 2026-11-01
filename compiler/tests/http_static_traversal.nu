// http_static_traversal.nu — regression for the serve_static
// path-traversal / arbitrary-file-read fix. Pure filesystem exercise (no
// socket), so it runs ungated like http_request_parser.
//
// The bug: __resolve_static_path stripped only ONE leading separator from
// the request path before joining with the served dir. A request for
// "//<abs>/secret" therefore became "/<abs>/secret", which path_join
// treats as an absolute `b` and returns VERBATIM — discarding the served
// dir and serving any file on the host. The fix strips ALL leading
// separators (so the tail is always relative) and rejects a tail that is
// still absolute (Windows drive-letter form) or contains a ".." segment.
//
// Second round: the path is percent-decoded BEFORE the checks (the
// filesystem sees decoded bytes, so "%2e%2e" must be judged as ".."),
// a bad escape or NUL is a 400, and a dot-segment other than
// ".well-known" is a 404. The symlink half lives in http_static_symlink
// (POSIX-only).
//
// We lay out:
//   <tmp>/secret.txt        — a "secret" OUTSIDE the served root
//   <tmp>/pubdir/index.html    — the served directory's index
//   <tmp>/pubdir/ok.txt        — a legitimate file
//   <tmp>/pubdir/a b.txt       — reachable only as "/a%20b.txt"
//   <tmp>/pubdir/.env          — a dotfile that must never be served
//   <tmp>/pubdir/.well-known/security.txt — the one dot-dir that is
// then drive serve_static with crafted request paths and assert that
// legitimate requests succeed (200) while every escape attempt is BLOCKED
// (NOT 200, and never serving the secret). main returns the failure count.

$ `stdlib/std/fs.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_static.nu`
$ `stdlib/ext/env.nu`

// Build a borrowed request with the given path. Caller frees with
// request_free.
@ mkreq s path → HttpRequest {
    : HttpRequest req ( request_new )
    ( string_free . req method )
    = . req method ( string_from `GET` )
    ( string_free . req path )
    = . req path ( string_from path )
    ^ req
}

// Run serve_static for `path`, return the status code, free everything.
@ status_for s dir s path → i {
    : HttpRequest req ( mkreq path )
    : HttpResponse resp ( serve_static dir req )
    : i st . resp status
    ( http_response_free resp )
    ( request_free req )
    ^ st
}

@ check_eq s label i got i want ( Vec i ) fails → v {
    ? == got want {
        ( nurl_print `  ok   ` ) ( nurl_print label )
        ( nurl_print ` = ` ) ( nurl_print ( nurl_str_int got ) ) ( nurl_print `\n` )
    } {
        ( nurl_print `  FAIL ` ) ( nurl_print label )
        ( nurl_print ` got ` ) ( nurl_print ( nurl_str_int got ) )
        ( nurl_print ` want ` ) ( nurl_print ( nurl_str_int want ) ) ( nurl_print `\n` )
        ( vec_push [i] fails 1 )
    }
}

// Assert the response is NOT 200 (the escape was blocked). Both 403 and
// 404 are acceptable "blocked" dispositions.
@ check_blocked s label i got ( Vec i ) fails → v {
    ? != got 200 {
        ( nurl_print `  ok   ` ) ( nurl_print label )
        ( nurl_print ` blocked (` ) ( nurl_print ( nurl_str_int got ) ) ( nurl_print `)\n` )
    } {
        ( nurl_print `  FAIL ` ) ( nurl_print label )
        ( nurl_print ` SERVED (200) — escape not blocked\n` )
        ( vec_push [i] fails 1 )
    }
}

@ run s base → i {
    : ( Vec i ) fails ( vec_new [i] )

    : String pubdir ( string_new )
    ( string_push_str pubdir base )
    ( string_push_str pubdir `/pubdir` )
    : s pubpath ( string_data pubdir )

    // Legitimate requests succeed.
    ( check_eq `GET /ok.txt` ( status_for pubpath `/ok.txt` ) 200 fails )
    ( check_eq `GET / (index)` ( status_for pubpath `/` ) 200 fails )

    // ".." traversal → 403.
    ( check_eq `GET /../secret.txt` ( status_for pubpath `/../secret.txt` ) 403 fails )

    // The core bug: a double-leading-slash absolute path that, pre-fix,
    // path_join would serve verbatim from outside `pubdir`.
    : String esc ( string_new )
    ( string_push_str esc `/` )
    ( string_push_str esc base )
    ( string_push_str esc `/secret.txt` )
    ( check_blocked `GET //<abs>/secret.txt` ( status_for pubpath ( string_data esc ) ) fails )
    ( string_free esc )

    // A bare absolute-style escape to a well-known path.
    ( check_blocked `GET //etc/hostname` ( status_for pubpath `//etc/hostname` ) fails )

    // Escapes are judged after decoding.
    ( check_eq `GET /a%20b.txt` ( status_for pubpath `/a%20b.txt` ) 200 fails )
    ( check_eq `GET /%6Fk.txt` ( status_for pubpath `/%6Fk.txt` ) 200 fails )
    ( check_eq `GET /%2e%2e/secret.txt` ( status_for pubpath `/%2e%2e/secret.txt` ) 403 fails )
    ( check_eq `GET /%2E%2E%2Fsecret.txt` ( status_for pubpath `/%2E%2E%2Fsecret.txt` ) 403 fails )
    ( check_eq `GET /..%5csecret.txt` ( status_for pubpath `/..%5csecret.txt` ) 403 fails )
    ( check_blocked `GET /%2f%2fetc/hostname` ( status_for pubpath `/%2f%2fetc/hostname` ) fails )
    ( check_eq `GET /C:%2fsecret.txt` ( status_for pubpath `/C:%2fsecret.txt` ) 403 fails )
    ( check_eq `GET /ok.txt%00.png` ( status_for pubpath `/ok.txt%00.png` ) 400 fails )
    ( check_eq `GET /ok%2` ( status_for pubpath `/ok%2` ) 400 fails )
    ( check_eq `GET /ok%zz` ( status_for pubpath `/ok%zz` ) 400 fails )

    // Dotfiles are not content; .well-known is.
    ( check_eq `GET /.env` ( status_for pubpath `/.env` ) 404 fails )
    ( check_eq `GET /%2eenv` ( status_for pubpath `/%2eenv` ) 404 fails )
    ( check_eq `GET /./ok.txt` ( status_for pubpath `/./ok.txt` ) 404 fails )
    ( check_eq `GET /.well-known/security.txt` ( status_for pubpath `/.well-known/security.txt` ) 200 fails )
    ( check_eq `GET /.well-known/.env` ( status_for pubpath `/.well-known/.env` ) 404 fails )
    ( check_eq `GET /x/.well-known/security.txt` ( status_for pubpath `/x/.well-known/security.txt` ) 404 fails )
    ( check_eq `GET /.well-knownx` ( status_for pubpath `/.well-knownx` ) 404 fails )

    ( string_free pubdir )
    : i n ( vec_len [i] fails )
    ( vec_free [i] fails )
    ^ n
}

@ main → i {
    // The platform's temp directory (env_temp_dir). A hardcoded /tmp only
    // works on Windows for as long as the C runtime's drive-relative
    // mapping happens to hold, and when it stops holding the symptom is
    // 404s three layers away.
    : String tdir ( env_temp_dir )
    : String base ( string_new )
    ( string_push_str base ( string_data tdir ) )
    ( string_push_str base `/nurl_static_traversal_test` )
    : s b ( string_data base )

    : String pubdir ( string_new )
    ( string_push_str pubdir b )
    ( string_push_str pubdir `/pubdir` )

    : !v IoErr d1 ( dir_create_all ( string_data pubdir ) )
    ?? d1 { T _ → {} F _ → { ( nurl_print `SETUP FAIL: dir_create_all\n` ) } }

    // secret OUTSIDE pubdir
    : String secret_path ( string_new )
    ( string_push_str secret_path b )
    ( string_push_str secret_path `/secret.txt` )
    : !v IoErr w1 ( write_file ( string_data secret_path ) `TOP-SECRET\n` )
    ?? w1 { T _ → {} F _ → { ( nurl_print `SETUP FAIL: write secret.txt\n` ) } }

    // index.html + ok.txt INSIDE pubdir
    : String idx ( string_new )
    ( string_push_str idx ( string_data pubdir ) )
    ( string_push_str idx `/index.html` )
    : !v IoErr w2 ( write_file ( string_data idx ) `<h1>index</h1>\n` )
    ?? w2 { T _ → {} F _ → { ( nurl_print `SETUP FAIL: write index.html\n` ) } }

    : String okp ( string_new )
    ( string_push_str okp ( string_data pubdir ) )
    ( string_push_str okp `/ok.txt` )
    : !v IoErr w3 ( write_file ( string_data okp ) `ok\n` )
    ?? w3 { T _ → {} F _ → { ( nurl_print `SETUP FAIL: write ok.txt\n` ) } }

    : String sp ( string_new )
    ( string_push_str sp ( string_data pubdir ) )
    ( string_push_str sp `/a b.txt` )
    : !v IoErr w4 ( write_file ( string_data sp ) `space\n` )
    ?? w4 { T _ → {} F _ → { ( nurl_print `SETUP FAIL: write a b.txt\n` ) } }
    ( string_free sp )

    : String envp ( string_new )
    ( string_push_str envp ( string_data pubdir ) )
    ( string_push_str envp `/.env` )
    : !v IoErr w5 ( write_file ( string_data envp ) `SECRET=1\n` )
    ?? w5 { T _ → {} F _ → { ( nurl_print `SETUP FAIL: write .env\n` ) } }
    ( string_free envp )

    : String wk ( string_new )
    ( string_push_str wk ( string_data pubdir ) )
    ( string_push_str wk `/.well-known` )
    : !v IoErr d2 ( dir_create_all ( string_data wk ) )
    ?? d2 { T _ → {} F _ → { ( nurl_print `SETUP FAIL: dir_create_all .well-known\n` ) } }
    ( string_push_str wk `/security.txt` )
    : !v IoErr w6 ( write_file ( string_data wk ) `Contact: x\n` )
    ?? w6 { T _ → {} F _ → { ( nurl_print `SETUP FAIL: write security.txt\n` ) } }
    ( string_free wk )

    : i fails ( run b )

    ( string_free okp )
    ( string_free idx )
    ( string_free secret_path )
    ( string_free pubdir )
    ( string_free base )

    ? == fails 0 {
        ( nurl_print `http_static_traversal: all checks passed\n` )
    } {
        ( nurl_print `http_static_traversal: FAILURES\n` )
    }
    ^ fails
}
