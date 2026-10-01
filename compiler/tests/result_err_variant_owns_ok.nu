// result_err_variant_owns_ok.nu — a `! T E` whose Err path names an enum
// variant (`F # E Closed`) still hands its Ok payload over.
//
// The cast reads the variant's global, and the rule for "this function
// builds a view out of something else" took that read for one: every such
// function counted as returning a view, its callers never dropped the Ok
// payload, and each call leaked it. Only a POINTER field read out of
// another value makes a view.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: | E { Closed }

@ empty_or_err i m → !( Vec u ) E {
    : ( Vec u ) v ( vec_new [u] )
    ? == m 1 { ^ @ !( Vec u ) E { T v } } {}
    ^ @ !( Vec u ) E { F # E Closed }
}

@ filled_or_err i m → !( Vec u ) E {
    : ( Vec u ) v ( vec_new [u] )
    ? == m 1 { ( vec_push [u] v # u 1 ) ^ @ !( Vec u ) E { T v } } {}
    ^ @ !( Vec u ) E { F # E Closed }
}

@ filled_or_none i m → ?( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ? == m 1 { ( vec_push [u] v # u 1 ) ^ @ ?( Vec u ) { T v } } {}
    ^ @ ?( Vec u ) { F # ( Vec u ) 0 }
}

@ main → i {
    : ~ i k 0
    : ~ i l ( live )
    ~ < k 10 { : !( Vec u ) E r ( empty_or_err 1 ) = k + k 1 }
    ( nurl_println ( nurl_str_cat `empty Ok, leaked: ` ( nurl_str_int - ( live ) l ) ) )
    = l ( live ) = k 0
    ~ < k 10 { : !( Vec u ) E r ( filled_or_err 1 ) = k + k 1 }
    ( nurl_println ( nurl_str_cat `filled Ok, leaked: ` ( nurl_str_int - ( live ) l ) ) )
    = l ( live ) = k 0
    ~ < k 10 { : !( Vec u ) E r ( filled_or_err 0 ) = k + k 1 }
    ( nurl_println ( nurl_str_cat `Err, leaked: ` ( nurl_str_int - ( live ) l ) ) )
    = l ( live ) = k 0
    ~ < k 10 { : ?( Vec u ) r ( filled_or_none 1 ) = k + k 1 }
    ( nurl_println ( nurl_str_cat `option, leaked: ` ( nurl_str_int - ( live ) l ) ) )
    ^ 0
}
