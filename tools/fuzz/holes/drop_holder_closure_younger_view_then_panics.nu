// drop_holder_closure_younger_view_then_panics: agora #259 — a `% Drop` holder given a view of a younger String by a closure, then a panic (drop_holder_closure_younger_view_then_panics).
// Closed: a view a callee stores into an `inout` argument (a whole assignment in its last statement, or a field of a struct of views; the argument at any position) and a view a closure gives one of its captures are dependencies of that argument or capture, where the call or the closure runs (mem_rawlit_unclaimed at the body's end, an `inout` struct of views as the keeping container, the closure effect `@vp=`; agora #259).
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
