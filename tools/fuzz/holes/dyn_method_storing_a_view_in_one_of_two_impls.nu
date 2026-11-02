// dyn_method_storing_a_view_in_one_of_two_impls: two impls, one storing the view and one not; the object holds either.
// Closed: a `dyn` method's virtual callee answers the holder/source question (g_fn_vkeeps) with the union of its impls' answers, and a parked caller is walked after the impls it may run (agora #394).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #394: two impls, one storing the view and one not; the object holds either
$ `stdlib/core/string.nu`

: W { s v }

% Fill [T] {
    @ fill T self inout W a String s → v
}

: Lens { i k }
: Nop { i k }

% Fill Nop { @ fill Nop n inout W a String s → v {} }

% Fill Lens { @ fill Lens l inout W a String s → v { = a @ W { ( string_data s ) } } }

@ main → i {
    : Nop n @ Nop { 1 }
    : %Fill d ( dyn Fill n )
    : ~ W a @ W { `x` }
    {
        : String s ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( fill d a s )
    }
    ( nurl_println . a v )
    : Lens l @ Lens { 1 }
    : %Fill e ( dyn Fill l )
    {
        : String s ( string_from `the second heap string, long enough to be on the heap for sure` )
        ( fill e a s )
    }
    ( nurl_println . a v )
    ^ 0
}
