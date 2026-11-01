// requires: live
// http_static_symlink.nu — serve_static must not follow a symlink out of
// the served directory. The name checks (no "..", no absolute tail, no
// dot-segment) keep the REQUEST under `dir`; a link inside `dir` that
// points at a file or directory elsewhere still led out until
// serve_static compared realpath(file) against realpath(dir)
// (`path_within`). A link that stays inside, and a served `dir` that is
// itself reached through a symlink, keep working.
//
// POSIX-only: it needs an unprivileged symlink(2). Windows skips it by
// name in run_tests.ps1, next to fs_glob_symlink.
//
// Layout under <tmp>/nurl_static_symlink_test:
//   secret.txt                — OUTSIDE the served root
//   outdir/also-secret.txt    — OUTSIDE, reached through a dir link
//   pub/ok.txt                — a plain file
//   pub/leak.txt   → ../secret.txt   (file link out)        → 404
//   pub/abs.txt    → <abs>/secret.txt (absolute link out)   → 404
//   pub/out        → ../outdir        (dir link out)        → 404
//   pub/alias.txt  → ok.txt           (link that stays in)  → 200
//   publink        → pub              (served dir is a link) → 200

$ `stdlib/std/fs.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_static.nu`
$ `stdlib/ext/env.nu`

@ status_for s dir s path → i {
    : HttpRequest req ( request_new )
    ( string_free . req path )
    = . req path ( string_from path )
    : HttpResponse resp ( serve_static dir req )
    : i st . resp status
    ( http_response_free resp )
    ( request_free req )
    ^ st
}

@ check s label i got i want → i {
    ? == got want {
        ( nurl_print `  ok   ` ) ( nurl_print label ) ( nurl_print ` = ` )
        ( nurl_print ( nurl_str_int got ) ) ( nurl_print `\n` )
        ^ 0
    } {}
    ( nurl_print `  FAIL ` ) ( nurl_print label ) ( nurl_print ` got ` )
    ( nurl_print ( nurl_str_int got ) ) ( nurl_print ` want ` )
    ( nurl_print ( nurl_str_int want ) ) ( nurl_print `\n` )
    ^ 1
}

@ cat2 s a s b → String {
    : String o ( string_from a )
    ( string_push_str o b )
    ^ o
}

@ put s path s body → v {
    : !v IoErr w ( write_file path body )
    ?? w { T _ → {} F _ → { ( nurl_print `SETUP FAIL: write ` ) ( nurl_print path ) ( nurl_print `\n` ) } }
}

@ link s target s at → v {
    : !v IoErr rm ( file_delete at )
    ? != 0 # i ( symlink target at ) {
        ( nurl_print `SETUP FAIL: symlink ` ) ( nurl_print at ) ( nurl_print `\n` )
    } {}
}

@ main → i {
    : String tdir ( env_temp_dir )
    : String base ( cat2 ( string_data tdir ) `/nurl_static_symlink_test` )
    : s b ( string_data base )
    : String pubd ( cat2 b `/pub` )
    : String outdir ( cat2 b `/outdir` )
    : !v IoErr d1 ( dir_create_all ( string_data pubd ) )
    ?? d1 { T _ → {} F _ → { ( nurl_print `SETUP FAIL: mkdir pub\n` ) } }
    : !v IoErr d2 ( dir_create_all ( string_data outdir ) )
    ?? d2 { T _ → {} F _ → { ( nurl_print `SETUP FAIL: mkdir outdir\n` ) } }

    : String secret ( cat2 b `/secret.txt` )
    ( put ( string_data secret ) `TOP-SECRET\n` )
    : String also ( cat2 b `/outdir/also-secret.txt` )
    ( put ( string_data also ) `TOP-SECRET\n` )
    : String okp ( cat2 b `/pub/ok.txt` )
    ( put ( string_data okp ) `ok\n` )

    : String l1 ( cat2 b `/pub/leak.txt` )
    ( link `../secret.txt` ( string_data l1 ) )
    : String l2 ( cat2 b `/pub/abs.txt` )
    ( link ( string_data secret ) ( string_data l2 ) )
    : String l3 ( cat2 b `/pub/out` )
    ( link `../outdir` ( string_data l3 ) )
    : String l4 ( cat2 b `/pub/alias.txt` )
    ( link `ok.txt` ( string_data l4 ) )
    : String l5 ( cat2 b `/publink` )
    ( link `pub` ( string_data l5 ) )

    : s p ( string_data pubd )
    : ~ i fails 0
    = fails + fails ( check `GET /ok.txt` ( status_for p `/ok.txt` ) 200 )
    = fails + fails ( check `GET /alias.txt (link inside)` ( status_for p `/alias.txt` ) 200 )
    = fails + fails ( check `GET /leak.txt (link ../)` ( status_for p `/leak.txt` ) 404 )
    = fails + fails ( check `GET /abs.txt (absolute link)` ( status_for p `/abs.txt` ) 404 )
    = fails + fails ( check `GET /out/also-secret.txt (dir link)` ( status_for p `/out/also-secret.txt` ) 404 )
    = fails + fails ( check `GET /nope.txt` ( status_for p `/nope.txt` ) 404 )
    = fails + fails ( check `GET /ok.txt via linked root` ( status_for ( string_data l5 ) `/ok.txt` ) 200 )
    = fails + fails ( check `GET /leak.txt via linked root` ( status_for ( string_data l5 ) `/leak.txt` ) 404 )

    ? == fails 0 {
        ( nurl_print `http_static_symlink: all checks passed\n` )
    } {
        ( nurl_print `http_static_symlink: FAILURES\n` )
    }
    ^ fails
}
