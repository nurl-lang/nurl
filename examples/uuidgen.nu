$ `stdlib/ext/uuid.nu`
$ `stdlib/core/string.nu`

@ main → v {
    // 1. Test generation
    : String v4 ( uuid_v4 )
    ( nurl_print `v4: ` )
    ( nurl_print ( string_data v4 ) )
    ( nurl_print `\n` )

    : String v7 ( uuid_v7 )
    ( nurl_print `v7: ` )
    ( nurl_print ( string_data v7 ) )
    ( nurl_print `\n` )

    // 2. Test round-trip
    : ?( Vec u ) p4 ( uuid_parse ( string_data v4 ) )
    ?? p4 {
        T b4 → {
            : String f4 ( uuid_format b4 )
            ( nurl_print `v4 formatted: ` )
            ( nurl_print ( string_data f4 ) )
            ( nurl_print `\n` )
            ? ( string_eq v4 f4 ) {
                ( nurl_print `v4 round-trip: OK\n` )
            } {
                ( nurl_print `v4 round-trip: FAIL\n` )
            }
            ( string_free f4 )
            ( vec_free [u] b4 )
        }
        F → { ( nurl_print `v4 parse: FAIL\n` ) }
    }

    // 3. Test invalid parse
    : ?( Vec u ) pinv ( uuid_parse `invalid-uuid-string` )
    ?? pinv {
        T b → {
            ( nurl_print `invalid parse: FAIL (should have failed)\n` )
            ( vec_free [u] b )
        }
        F → { ( nurl_print `invalid parse: OK\n` ) }
    }

    ( string_free v4 )
    ( string_free v7 )
}
