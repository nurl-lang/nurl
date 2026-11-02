// dyn_method_storing_a_view_into_its_inout_holder: a call through a trait object whose impl stores a view of one argument into another.
// Closed: a `dyn` method's virtual callee answers the holder/source question (g_fn_vkeeps) with the union of its impls' answers, and a parked caller is walked after the impls it may run (agora #394).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #394: a call through a trait object whose impl stores a view of one argument into another
$ `stdlib/core/string.nu`

: W { s v }

% Fill [T] {
    @ fill T self inout W a String s → v
}

: Lens { i k }

% Fill Lens { @ fill Lens l inout W a String s → v { = a @ W { ( string_data s ) } } }

@ main → i {
    : Lens l @ Lens { 1 }
    : %Fill d ( dyn Fill l )
    : ~ W a @ W { `x` }
    {
        : String s ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( fill d a s )
    }
    ( nurl_println . a v )
    ^ 0
}
