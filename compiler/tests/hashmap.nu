// HashMap runtime test — string keys, int values.
//
// Exercises the generic `stdlib/std/hashmap.nu` HashMap[K V]
// instantiated at [s i]: new / put / get / size / contains /
// overwrite / delete / free.

$ `stdlib/std/hashmap.nu`
$ `stdlib/core/option.nu`

@ main → i {
    ( nurl_print `HashMap test...\n` )

    // Closures bridging the stock @-fns to higher-order parameters.
    // NURL passes (fn-ptr + env) pairs, not bare @-fn names.
    : ( @ i s ) hs \ s str → i { ^ ( hash_string str ) }
    : ( @ b s s ) es \ s a s b → b { ^ ( eq_string a b ) }

    // Create
    : ( HashMap s i ) m ( map_new [s i] )

    // Put
    ( map_set [s i] m `alice` 42 hs es )
    ( map_set [s i] m `bob` 17 hs es )
    ( map_set [s i] m `charlie` 99 hs es )

    // Get
    ( nurl_print `alice: ` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ( map_get [s i] m `alice` hs es ) 0 ) ) )
    ( nurl_print `\n` )

    ( nurl_print `bob: ` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ( map_get [s i] m `bob` hs es ) 0 ) ) )
    ( nurl_print `\n` )

    // Size
    ( nurl_print `size: ` )
    ( nurl_print ( nurl_str_int ( map_len [s i] m ) ) )
    ( nurl_print `\n` )

    // Has
    ( nurl_print `has alice: ` )
    ( nurl_print ? ( map_contains [s i] m `alice` hs es ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `has dave: ` )
    ( nurl_print ? ( map_contains [s i] m `dave` hs es ) `yes` `no` )
    ( nurl_print `\n` )

    // Overwrite
    ( map_set [s i] m `alice` 100 hs es )
    ( nurl_print `alice after update: ` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] ( map_get [s i] m `alice` hs es ) 0 ) ) )
    ( nurl_print `\n` )

    // Delete
    ( map_remove [s i] m `bob` hs es )
    ( nurl_print `has bob after del: ` )
    ( nurl_print ? ( map_contains [s i] m `bob` hs es ) `yes` `no` )
    ( nurl_print `\n` )

    ( nurl_print `size after del: ` )
    ( nurl_print ( nurl_str_int ( map_len [s i] m ) ) )
    ( nurl_print `\n` )

    // Cleanup
    ( map_free [s i] m )

    ( nurl_print `done\n` )
    ^ 0
}
