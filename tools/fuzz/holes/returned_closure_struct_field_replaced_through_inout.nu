// returned_closure_struct_field_replaced_through_inout: h308 for a struct the returned closure captured by value: a callee replacing one of its Vec fields through `inout` released the Vec the closure's copy of the struct still held.
// Closed: as h307 — g_fn_replaces names an `inout` parameter an owned field of which the callee may replace.
// main (before this PR): AddressSanitizer reported heap-use-after-free in vec_at, called from the closure.
// map: §2.11 | A2 | rejected | h309 | h308 for a struct whose Vec field the inout callee replaces
$ `stdlib/core/vec.nu`

: Bag { ( Vec i ) items }

@ mk Bag b → ( @ i ) { ^ \ → i { ^ ( vec_at [i] . b items 0 ) } }

@ swap_items inout Bag b → v { = . b items ( vec_new [i] ) ( vec_push [i] . b items 8 ) }

@ main → i {
    : ~ Bag b @ Bag { ( vec_new [i] ) }
    ( vec_push [i] . b items 7 )
    : ( @ i ) f ( mk b )
    ( swap_items b )
    ( nurl_println_int ( f ) )
    ^ 0
}
