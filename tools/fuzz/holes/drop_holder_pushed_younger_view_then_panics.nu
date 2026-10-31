// drop_holder_pushed_younger_view_then_panics: agora #254 — a W with a view of a younger String pushed into a Vec of W, then a panic (drop_holder_pushed_younger_view_then_panics).
// Closed: a holder whose drop may read views gains no view of a binding declared after it — refused where the view is gained (an assignment, a push into it), so no drop order, a scope's end or a panic's unwind, frees the source first (bck_younger_view_check; agora #254).
// main: rejected, but only where the String's block ends on the normal path (#224's rule); the push itself was not asked.
// map: §7.6 | A2 | rejected | - | agora #254: a W with a view of a younger String pushed into a Vec of W, then a panic
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ f i n → v {
    : String a ( string_from `the outer string, which outlives the holders` )
    : ( Vec W ) ws ( vec_new [W] )
    ? == n 1 {
        : String b ( string_from `the inner string, which the unwind frees before the holder reads it` )
        ( vec_push [W] ws @ W { ( string_data b ) } )
        ( panic `boom` )
    } {}
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( f 1 ) } )
    ( puts `ran` )
    ^ 0
}
