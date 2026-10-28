// field_handover_ok.nu — a field handed to a callee that takes it, from
// every binding that may give it (agora #145): an owned local, a
// parameter the function then takes over (an inferred `sink`), a `sink`
// or `inout` parameter, a Vec slot read with vec_get, a binding read out
// of an owned local's field, and a closure's parameter (a copy). Each is
// emptied where it lives, so nothing is released twice; and a field a
// closure assigns through its by-reference capture releases what it held
// (agora #144). The sanitizer corpus holds each to no use after free and
// no leak (h389–h407).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Pair { String a String b }

@ mk s t → String { ^ ( string_from t ) }

@ pair → Pair { ^ @ Pair { ( mk `alpha` ) ( mk `beta` ) } }

// Takes its parameter: hands one field on and drops the other.
@ drop_a Pair p → v { ( string_free . p a ) }

@ take_sink sink Pair p → v {
    ( nurl_println ( string_data . p b ) )
    ( string_free . p a )
}

@ take_inout inout Pair p → v { ( string_free . p a ) }

@ main → i {
    // An owned local: its own drop skips the emptied field.
    : Pair l ( pair )
    ( string_free . l a )
    ( nurl_println ( string_data . l b ) )

    // A parameter the callee takes over: the call moves the binding.
    : Pair q ( pair )
    ( drop_a q )
    : Pair r ( pair )
    ( take_sink r )

    // `inout`: emptied in the caller's own struct.
    : ~ Pair w ( pair )
    ( take_inout w )
    ( nurl_println ( string_data . w b ) )
    ( nurl_println ( nurl_str_int ( string_len . w a ) ) )

    // A Vec slot read with vec_get: the slot is emptied.
    : ( Vec Pair ) vs ( vec_new [Pair] )
    ( vec_push [Pair] vs ( pair ) )
    ?? ( vec_get [Pair] vs 0 ) { T e → { ( string_free . e a ) } F → {} }
    ?? ( vec_get [Pair] vs 0 ) { T e → { : String n . e b ( string_free n ) } F → {} }
    ( vec_free [Pair] vs )

    // A binding read out of an owned local's field, taken whole.
    : Pair v ( pair )
    : String n . v a
    ( string_free n )
    ( nurl_println ( string_data . v b ) )

    // A field a closure assigns through its by-reference capture: the old
    // value is released under the binding's drop flag (agora #144).
    : ~ Pair c ( pair )
    : ( @ v ) set_b \ → v { = . c b ( mk `gamma` ) }
    ( set_b )
    ( set_b )
    ( nurl_println ( string_data . c b ) )

    // A closure's parameter is lent: what it hands on is a copy of it.
    : ( Vec Pair ) hs ( vec_new [Pair] )
    ( vec_push [Pair] hs ( pair ) )
    ( vec_free_with [Pair] hs \ Pair h → v { ( string_free . h a ) } )
    ( nurl_println `done` )
    ^ 0
}
