// dyn_methods_storing_no_view_run_clean: a dyn call whose impls store no view of the argument.
// Must keep compiling and running clean: a `dyn` method's virtual callee answers the holder/source question (g_fn_vkeeps) with the union of its impls' answers, and a parked caller is walked after the impls it may run (agora #394).
// main's compiler: compiled, ran clean.
// map: §2.7 | A2 | runs-clean | - | agora #394 guard: a dyn call whose impls store no view of the argument
$ `stdlib/core/string.nu`

: W { s v }

% Fill [T] {
    @ fill T self inout W a String s → v
}

: Lens { i k }
: Nop { i k }

% Fill Nop { @ fill Nop n inout W a String s → v {} }

% Fill Lens { @ fill Lens l inout W a String s → v { = a @ W { `lit` } } }

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
