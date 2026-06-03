// registry_index_basic.nu — registry index parse + version selection.
//
// Covers: JSON index parse (name + versions + per-version checksum/yanked/
// deps), highest-satisfying selection with yanked exclusion, and the
// content-addressed tarball URL builder.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/registry_index.nu`

@ sel RegIndex idx s req → v {
    : i k ( regindex_select idx req )
    ( nurl_print `select ` ) ( nurl_print req ) ( nurl_print ` -> ` )
    ? < k 0 {
        ( nurl_print `none\n` )
    } {
        : ?IdxVersion vo ( vec_get [IdxVersion] . idx versions k )
        ?? vo {
            T v → { ( nurl_print ( string_data . v version ) ) ( nurl_print `\n` ) }
            F → ( nurl_print `?\n` )
        }
    }
}

@ main → i {
    : s src `{
  "name": "foo",
  "versions": [
    { "version": "1.0.0", "checksum": "aaa", "yanked": false, "deps": [] },
    { "version": "1.2.0", "checksum": "bbb", "yanked": false, "deps": [ { "name": "bar", "req": "^0.3" } ] },
    { "version": "1.4.0", "checksum": "ccc", "yanked": true, "deps": [] },
    { "version": "2.0.0", "checksum": "ddd", "yanked": false, "deps": [] }
  ]
}`
    : !RegIndex RegIndexErr ir ( regindex_parse src )
    ?? ir {
        F e → ( nurl_print ( regindex_err_name e ) )
        T idx → {
            ( nurl_print `name=` ) ( nurl_print ( string_data . idx name ) ) ( nurl_print `\n` )
            ( nurl_print `versions=` ) ( nurl_print_int ( vec_len [IdxVersion] . idx versions ) ) ( nurl_print `\n` )

            ( sel idx `^1.0.0` )     // 1.2.0 (1.4.0 yanked, 2.0.0 out of range)
            ( sel idx `>=1.0.0` )    // 2.0.0
            ( sel idx `^1.3.0` )     // none (only 1.4.0 in range, but yanked)
            ( sel idx `=2.0.0` )     // 2.0.0
            ( sel idx `^3.0.0` )     // none

            : i k2 ( regindex_select idx `=1.2.0` )
            : ?IdxVersion v2 ( vec_get [IdxVersion] . idx versions k2 )
            ?? v2 {
                T v → {
                    ( nurl_print `v120_checksum=` ) ( nurl_print ( string_data . v checksum ) ) ( nurl_print `\n` )
                    ( nurl_print `v120_deps=` ) ( nurl_print_int ( vec_len [IdxDep] . v deps ) ) ( nurl_print `\n` )
                    : ?IdxDep d0 ( vec_get [IdxDep] . v deps 0 )
                    ?? d0 {
                        T d → { ( nurl_print `dep0=` ) ( nurl_print ( string_data . d name ) ) ( nurl_print ` ` ) ( nurl_print ( string_data . d req ) ) ( nurl_print `\n` ) }
                        F → {}
                    }
                }
                F → {}
            }

            : String url ( regindex_tarball_url `https://reg.nurl-lang.org` `foo` `1.2.0` )
            ( nurl_print `url=` ) ( nurl_print ( string_data url ) ) ( nurl_print `\n` )
            ( string_free url )
            ( regindex_free idx )
        }
    }
    ( nurl_print `done\n` )
    ^ 0
}
