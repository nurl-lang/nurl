// Test: stdlib/std/hashmap.nu — map_keys / map_values
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ( @ i i i ) c_int \ i a i b → i { ^ ( cmp_int a b ) }
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ ( eq_int a b ) }

    : ( HashMap i i ) m ( map_new [i i] )
    ( map_set [i i] m 1 100 hi ei )
    ( map_set [i i] m 2 200 hi ei )
    ( map_set [i i] m 3 300 hi ei )
    ( map_set [i i] m 4 400 hi ei )

    : ( Vec i ) ks ( map_keys [i i] m )
    : ( Vec i ) vs ( map_values [i i] m )

    ( nurl_print `klen=` )
    ( nurl_print ( nurl_str_int ( vec_len [i] ks ) ) )
    ( nurl_print ` vlen=` )
    ( nurl_print ( nurl_str_int ( vec_len [i] vs ) ) )
    ( nurl_print `\n` )

    // sort to get deterministic output (host probe order is not stable)
    ( sort_by [i] ks c_int )
    ( sort_by [i] vs c_int )

    ( nurl_print `keys=` )
    : ~ i i 0
    ~ < i ( vec_len [i] ks ) {
        : ?i g ( vec_get [i] ks i )
        ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] g 0 ) ) )
        ( nurl_print ` ` )
        = i + i 1
    }
    ( nurl_print `\n` )

    ( nurl_print `vals=` )
    = i 0
    ~ < i ( vec_len [i] vs ) {
        : ?i g ( vec_get [i] vs i )
        ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] g 0 ) ) )
        ( nurl_print ` ` )
        = i + i 1
    }
    ( nurl_print `\n` )

    // remove a key, keys/values shrink accordingly
    : ?i removed ( map_remove [i i] m 2 hi ei )
    ( vec_free [i] ks )
    ( vec_free [i] vs )

    : ( Vec i ) ks2 ( map_keys [i i] m )
    ( sort_by [i] ks2 c_int )
    ( nurl_print `after_remove keys=` )
    = i 0
    ~ < i ( vec_len [i] ks2 ) {
        : ?i g ( vec_get [i] ks2 i )
        ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] g 0 ) ) )
        ( nurl_print ` ` )
        = i + i 1
    }
    ( nurl_print `\n` )

    // empty map → empty vecs
    ( vec_free [i] ks2 )
    : ( HashMap i i ) e ( map_new [i i] )
    : ( Vec i ) ek ( map_keys [i i] e )
    : ( Vec i ) ev ( map_values [i i] e )
    ( nurl_print `empty_keys_len=` )
    ( nurl_print ( nurl_str_int ( vec_len [i] ek ) ) )
    ( nurl_print ` empty_vals_len=` )
    ( nurl_print ( nurl_str_int ( vec_len [i] ev ) ) )
    ( nurl_print `\n` )

    ( vec_free [i] ev )
    ( vec_free [i] ek )
    ( map_free [i i] e )
    ( map_free [i i] m )
    ( nurl_print `done\n` )
    ^ 0
}
