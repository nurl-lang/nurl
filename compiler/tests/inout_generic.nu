// inout_generic.nu — `inout` and `sink` parameter conventions on
// GENERIC functions.
//
// A parameter convention is a property of parameter POSITION, not of
// the type arguments — so the `inout` / `sink` index sets are computed
// once from the generic template (compute_generic_inout_sink, keyed by
// the generic name) and a call site resolves them by that name even
// though the monomorphised instantiation is emitted later (deferred).
//
// Exercises: `inout` on a scalar parameter beside a tparam-typed
// by-value parameter, `inout` on a generic-struct parameter, a `sink`
// of a generic-struct value, and two distinct instantiations of the
// same generic `inout` function.

// A generic struct, to exercise `inout` / `sink` on a generic type.
: Box [A] { A val  i tag }

// inout on a concrete scalar parameter, beside a tparam-typed
// by-value parameter — instantiated below at both [i] and [s].
@ store_g [A] inout i slot  A item → v {
    = slot + slot 1
}

// inout on a generic-struct parameter: mutate the caller's Box.
@ retag_g [A] inout ( Box A ) b → v {
    = . b tag + . b tag 100
}

// sink on a generic-struct value: the callee consumes `b`. Box[i] has
// no owned fields, so the move is clean (no auto-drop to transfer).
@ tag_of_g [A] sink ( Box A ) b → i {
    ^ . b tag
}

@ main → i {
    : ~ i n 0
    ( store_g [i] n 7 )            // n = 1
    ( store_g [s] n `hi` )         // n = 2  (a second instantiation)
    : ~ ( Box i ) bi @ ( Box i ) { 5 10 }
    ( retag_g [i] bi )             // bi.tag = 110
    : i t ( tag_of_g [i] bi )      // bi is consumed here
    ( nurl_print `n=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
    ( nurl_print `tag=` ) ( nurl_print ( nurl_str_int t ) ) ( nurl_print `\n` )
    ^ 0
}
