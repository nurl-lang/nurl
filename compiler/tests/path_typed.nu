// path_typed.nu — exercises the typed Path layer added to
// stdlib/std/path.nu: the Path { String inner } wrapper, its
// constructors / accessors, and the two new operations path_canonical
// (realpath) and path_relative_to (lexical relative path).
//
// Each line prints `<label>: ok` on success, `<label>: FAIL ...`
// otherwise — correctness is checked in the test, not just snapshotted.
//
// Expected output:
//   new+str: ok
//   parent: ok
//   name: ok
//   push: ok
//   is_abs yes: ok
//   is_abs no: ok
//   is_empty: ok
//   clone eq: ok
//   eq diff: ok
//   rel updown: ok
//   rel down: ok
//   rel same: ok
//   rel mismatch: ok
//   canonical abs: ok
//   canonical missing: ok

$ `stdlib/std/path.nu`
$ `stdlib/core/string.nu`

@ expect_str s label s got s want → v {
    ? != 0 ( nurl_str_eq got want ) {
        ( nurl_print label )
        ( nurl_print `: ok\n` )
    } {
        ( nurl_print label )
        ( nurl_print `: FAIL got '` )
        ( nurl_print got )
        ( nurl_print `'\n` )
    }
}

@ expect_b s label b got b want → v {
    ? == got want {
        ( nurl_print label )
        ( nurl_print `: ok\n` )
    } {
        ( nurl_print label )
        ( nurl_print `: FAIL\n` )
    }
}

@ main → i {
    // ── Construction + accessors ────────────────────────────────────
    : Path p1 ( path_new `/usr/local/bin` )
    ( expect_str `new+str` ( path_str p1 ) `/usr/local/bin` )

    : Path par ( path_parent p1 )
    ( expect_str `parent` ( path_str par ) `/usr/local` )
    ( path_free par )

    : Path nm ( path_name p1 )
    ( expect_str `name` ( path_str nm ) `bin` )
    ( path_free nm )

    : Path usr ( path_new `/usr` )
    : Path ul ( path_push usr `local` )
    ( expect_str `push` ( path_str ul ) `/usr/local` )
    ( path_free usr )
    ( path_free ul )

    ( expect_b `is_abs yes` ( path_is_abs p1 ) T )
    : Path rel ( path_new `rel/path` )
    ( expect_b `is_abs no` ( path_is_abs rel ) F )

    : Path empty ( path_new `` )
    ( expect_b `is_empty` ( path_is_empty empty ) T )
    ( path_free empty )

    : Path c1 ( path_clone p1 )
    ( expect_b `clone eq` ( path_eq p1 c1 ) T )
    ( path_free c1 )
    ( expect_b `eq diff` ( path_eq p1 rel ) F )
    ( path_free rel )
    ( path_free p1 )

    // ── path_relative_to ────────────────────────────────────────────
    : Path b1 ( path_new `/a/b/c` )

    : Path t1 ( path_new `/a/b/d/e` )
    ?? ( path_relative_to b1 t1 ) {
        T r → { ( expect_str `rel updown` ( path_str r ) `../d/e` ) ( path_free r ) }
        F → ( nurl_print `rel updown: FAIL none\n` )
    }
    ( path_free t1 )

    : Path t2 ( path_new `/a/b/c/x/y` )
    ?? ( path_relative_to b1 t2 ) {
        T r → { ( expect_str `rel down` ( path_str r ) `x/y` ) ( path_free r ) }
        F → ( nurl_print `rel down: FAIL none\n` )
    }
    ( path_free t2 )

    : Path b1c ( path_new `/a/b/c` )
    ?? ( path_relative_to b1 b1c ) {
        T r → { ( expect_str `rel same` ( path_str r ) `.` ) ( path_free r ) }
        F → ( nurl_print `rel same: FAIL none\n` )
    }
    ( path_free b1c )
    ( path_free b1 )

    : Path ab ( path_new `/abs/x` )
    : Path rl ( path_new `rel/y` )
    ?? ( path_relative_to ab rl ) {
        T r → { ( nurl_print `rel mismatch: FAIL some\n` ) ( path_free r ) }
        F → ( nurl_print `rel mismatch: ok\n` )
    }
    ( path_free ab )
    ( path_free rl )

    // ── path_canonical ──────────────────────────────────────────────
    // "." resolves to the (host-dependent) absolute CWD — assert only
    // that the result is absolute, not its exact text.
    : Path dot ( path_new `.` )
    ?? ( path_canonical dot ) {
        T r → { ( expect_b `canonical abs` ( path_is_abs r ) T ) ( path_free r ) }
        F → ( nurl_print `canonical abs: FAIL none\n` )
    }
    ( path_free dot )

    : Path bad ( path_new `/no/such/path/xyz123456` )
    ?? ( path_canonical bad ) {
        T r → { ( nurl_print `canonical missing: FAIL some\n` ) ( path_free r ) }
        F → ( nurl_print `canonical missing: ok\n` )
    }
    ( path_free bad )

    ^ 0
}
