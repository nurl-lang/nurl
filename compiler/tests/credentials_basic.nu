// credentials_basic.nu — ~/.nurl/credentials set / get / upsert / remove.
//
// Writes under $HOME/.nurl, so it is GATED behind NURL_CREDS_TESTS=1 (and
// meant to be run with HOME pointed at a throwaway dir) to never touch a
// real credentials file during the default corpus run.

$ `stdlib/ext/credentials.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

@ ignore !v IoErr r → v { ?? r { T _ → {} F _ → {} } }

@ show s label s reg → v {
    : String t ( creds_get reg )
    ( nurl_print label ) ( nurl_print `=` )
    ? > ( string_len t ) 0 { ( nurl_print ( string_data t ) ) } { ( nurl_print `<none>` ) }
    ( nurl_print `\n` )
    ( string_free t )
}

@ run → v {
    : s r1 `https://reg.a/`
    : s r2 `https://reg.b/`
    ( ignore ( creds_set r1 `tok-a1` ) )
    ( show `a` r1 )                 // tok-a1
    ( ignore ( creds_set r2 `tok-b1` ) )
    ( show `a_keep` r1 )            // tok-a1 (still there after 2nd registry)
    ( show `b` r2 )                 // tok-b1
    ( ignore ( creds_set r1 `tok-a2` ) )
    ( show `a_upsert` r1 )          // tok-a2 (replaced, not duplicated)
    ( show `b_keep` r2 )            // tok-b1
    ( ignore ( creds_remove r1 ) )
    ( show `a_removed` r1 )         // <none>
    ( show `b_final` r2 )           // tok-b1
    ( ignore ( creds_remove r2 ) )
}

@ main → i {
    : ?String g ( env_get `NURL_CREDS_TESTS` )
    ?? g {
        T s → { ( string_free s ) ( run ) ( nurl_print `done\n` ) }
        F → { ( nurl_print `credentials test skipped (set NURL_CREDS_TESTS=1)\n` ) }
    }
    ^ 0
}
