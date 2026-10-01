// returns_inside_borrowed_match.nu — a function whose every arm of a match over
// a borrowed scrutinee returns a fresh value hands its caller an owned one.
//
// `?? ( vec_get [String] v 0 ) { T l → { ^ ( string_from … ) } F _ → { ^ … } }`:
// no path falls off the end, but the scrutinee's borrow was still on the
// "last value" channel when the body ended, and the implicit-return rule took
// it for the function's result — the function counted as a lender, and no
// caller dropped what it returned (the anomaly package leaked every point it
// parsed this way, model_point_json).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ f1 ( Vec String ) v → ?String {
    ?? ( vec_get [String] v 0 ) {
        T l → { ^ @ ?String { T ( string_from ( string_data l ) ) } }
        F _ → { ^ @ ?String { F } }
    }
}

@ f2 ( Vec String ) v → ?String {
    ?? ( vec_get [String] v 0 ) {
        T l → { : String c ( string_from ( string_data l ) ) ^ @ ?String { T c } }
        F _ → { ^ @ ?String { F } }
    }
}

@ f3 ( Vec String ) v → String {
    ?? ( vec_get [String] v 0 ) {
        T l → { ^ ( string_from ( string_data l ) ) }
        F _ → { ^ ( string_new ) }
    }
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( string_from `x` ) )
    : ~ i l - ( nurl_alloc_count ) ( nurl_free_count ) : ~ i k 0
    ~ < k 20 { : ?String r ( f1 v ) = k + k 1 } ( nurl_println ( nurl_str_cat `f1 ` ( nurl_str_int - - ( nurl_alloc_count ) ( nurl_free_count ) l ) ) )
    = l - ( nurl_alloc_count ) ( nurl_free_count ) = k 0
    ~ < k 20 { : ?String r ( f2 v ) = k + k 1 } ( nurl_println ( nurl_str_cat `f2 ` ( nurl_str_int - - ( nurl_alloc_count ) ( nurl_free_count ) l ) ) )
    = l - ( nurl_alloc_count ) ( nurl_free_count ) = k 0
    ~ < k 20 { : String r ( f3 v ) = k + k 1 } ( nurl_println ( nurl_str_cat `f3 ` ( nurl_str_int - - ( nurl_alloc_count ) ( nurl_free_count ) l ) ) )
    ^ 0
}
