// Test: compound type-args `( Vec ( Pair K V ) )` in struct fields,
// locals, and return types. Previously parse_type_paren read raw
// tokens and miscompiled nested generics — caller had to wrap them
// in named structs (see HTTP_SERVER_PLAN.md cross-cutting prereq).

$ `stdlib/core/vec.nu`
$ `stdlib/core/pair.nu`

// Local binding with compound type-arg.
@ make_pairs → ( Vec ( Pair s i ) ) {
    : ( Vec ( Pair s i ) ) v ( vec_new [( Pair s i )] )
    ( vec_push [( Pair s i )] v ( pair_new [s i] `alpha` 1 ) )
    ( vec_push [( Pair s i )] v ( pair_new [s i] `beta` 2 ) )
    ( vec_push [( Pair s i )] v ( pair_new [s i] `gamma` 3 ) )
    ^ v
}

// Struct field with compound type-arg.
: Bag {
    ( Vec ( Pair s i ) ) entries
}

@ main → i {
    : ( Vec ( Pair s i ) ) v ( make_pairs )
    ( nurl_print `len=` )
    ( nurl_print ( nurl_str_int ( vec_len [( Pair s i )] v ) ) )
    ( nurl_print `\n` )

    // Iterate via index — vec_data + raw pointer walk because vec_get
    // for multi-field structs is the OTHER cross-cutting prereq.
    : *( Pair s i ) data ( vec_data [( Pair s i )] v )
    : i n ( vec_len [( Pair s i )] v )
    : ~ i k 0
    ~ < k n {
        : ( Pair s i ) p . data k
        ( nurl_print ( pair_first [s i] p ) )
        ( nurl_print `=` )
        ( nurl_print ( nurl_str_int ( pair_second [s i] p ) ) )
        ( nurl_print `\n` )
        = k + k 1
    }

    ( vec_free [( Pair s i )] v )

    // Struct with compound-typed field.
    : ( Vec ( Pair s i ) ) v2 ( vec_new [( Pair s i )] )
    ( vec_push [( Pair s i )] v2 ( pair_new [s i] `solo` 99 ) )
    : Bag b @ Bag { v2 }
    : ( Vec ( Pair s i ) ) be . b entries
    ( nurl_print `bag_len=` )
    ( nurl_print ( nurl_str_int ( vec_len [( Pair s i )] be ) ) )
    ( nurl_print `\n` )
    ( vec_free [( Pair s i )] be )

    ^ 0
}
