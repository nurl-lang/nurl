// generic_option_types.nu — generics instantiated over OPTION element
// types: `Vec ?String`, `Vec ?i`, `vec_get [?T]` → `??T`, nested `??`
// matching, `??T` as function param/return, and closures with `?T`
// parameters (the `vec_free_with` drop). Regression guard for the
// option-typed-generics feature.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// `??String` as a parameter type + nested option match.
@ show_str ??String o → s {
    ?? o {
        T inner → ?? inner { T sv → ^ ( string_data sv )  F _ → ^ `<null>` }
        F _ → ^ `<oob>`
    }
}

// `??i` as a return type (forwarding vec_get) + as a parameter type.
@ pick_int ( Vec ?i ) v i idx → ??i {
    ^ ( vec_get [?i] v idx )
}

@ render_int ??i o → i {
    ?? o {
        T inner → ?? inner { T x → ^ x  F _ → ^ -1 }
        F _ → ^ -999
    }
}

@ test_string_vec → v {
    : ( Vec ?String ) v ( vec_with_cap [?String] 4 )
    ( vec_push [?String] v @ ?String { T ( string_from `alpha` ) } )
    ( vec_push [?String] v @ ?String { F # String 0 } )
    ( vec_push [?String] v @ ?String { T ( string_from `gamma` ) } )
    // overwrite the NULL slot with a value via vec_set
    ( vec_set [?String] v 1 @ ?String { T ( string_from `beta` ) } )
    : ~ i k 0
    ~ < k 4 {
        ( nurl_print `str[` ) ( nurl_print ( nurl_str_int k ) ) ( nurl_print `]=` )
        ( nurl_print ( show_str ( vec_get [?String] v k ) ) ) ( nurl_print `\n` )
        = k + k 1
    }
    // Drop closure takes a `?String` parameter (aggregate closure param).
    ( vec_free_with [?String] v \ ?String o → v { ?? o { T sv → ( string_free sv )  F _ → {} } } )
}

@ test_int_vec → v {
    : ( Vec ?i ) v ( vec_with_cap [?i] 3 )
    ( vec_push [?i] v @ ?i { T 10 } )
    ( vec_push [?i] v @ ?i { F # i 0 } )
    ( vec_push [?i] v @ ?i { T 30 } )
    : ~ i k 0
    ~ < k 4 {
        ( nurl_print `int[` ) ( nurl_print ( nurl_str_int k ) ) ( nurl_print `]=` )
        ( nurl_print ( nurl_str_int ( render_int ( pick_int v k ) ) ) ) ( nurl_print `\n` )
        = k + k 1
    }
    ( vec_free [?i] v )
}

@ main → i {
    ( test_string_vec )
    ( test_int_vec )
    ^ 0
}
