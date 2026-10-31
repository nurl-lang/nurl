// drop_holder_views_inner_then_panics: agora #254 — a W re-pointed to a view of a younger String, then a panic before it is pointed back: the unwind frees the String first (drop_holder_views_inner_then_panics).
// Closed: a holder whose drop may read views gains no view of a binding declared after it — refused where the view is gained (an assignment, a push into it), so no drop order, a scope's end or a panic's unwind, frees the source first (bck_younger_view_check; agora #254).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #254: a W re-pointed to a view of a younger String, then a panic before it is pointed back: the unwind frees the String first
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ f i n → v {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ W w @ W { ( string_data a ) }
    ? == n 1 {
        : String b ( string_from `the inner string, which the unwind frees before the holder's destructor reads it` )
        = w @ W { ( string_data b ) }
        ( panic `boom` )
        = w @ W { ( string_data a ) }
    } {}
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( f 1 ) } )
    ( puts `ran` )
    ^ 0
}
