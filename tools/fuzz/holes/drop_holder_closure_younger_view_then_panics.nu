// drop_holder_closure_younger_view_then_panics: agora #259 — a `% Drop` holder given a view of a younger String by a closure, then a panic (drop_holder_closure_younger_view_then_panics).
// Closed: a closure cannot give one of its captures, or its own `inout` parameter, a value that may hold a view — a whole assignment, a field store, a push or keep the callee really stores — since a closure's type does not say what running it stores, so nothing where it runs follows the view; A2's CapsOK and Implements (__clo_cap_marks, bck_clo_cap_view_diag, agora #312; #259 made it a dependency where the closure ran).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.14 | A2 | rejected | - | agora #259: a `% Drop` holder given a view of a younger String by a closure, then a panic
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ f i n → v {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ W w @ W { ( string_data a ) }
    ? == n 1 {
        : String b ( string_from `the inner string, which the unwind frees before the holder reads it` )
        : ( @ v ) repoint \ → v { = w @ W { ( string_data b ) } }
        ( repoint )
        ( panic `boom` )
        = w @ W { ( string_data a ) }
    } {}
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( f 1 ) } )
    ( puts `ran` )
    ^ 0
}
