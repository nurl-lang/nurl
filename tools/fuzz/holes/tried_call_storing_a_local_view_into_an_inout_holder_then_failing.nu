// tried_call_storing_a_local_view_into_an_inout_holder_then_failing: `: i x \ ( setw w ( string_data b ) k )`: the tried call stores a view of the callee local b into the inout holder w, then fails; the `\` hands w back viewing b (PO e02).
// Closed: the `\` way out is checked on the state after the tried call's own rows (agora #406).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #406: `: i x \ ( setw w ( string_data b ) k )`: the tried call stores a view of the callee local b into the inout holder w, then fails; the `\` hands w back viewing b (PO e02)
$ `stdlib/core/string.nu`

: W { s v }
: | E { Bad i }

@ setw inout W w s v i k → !i E {
    = w @ W { v }
    ? > k 0 { ^ @ !i E { F @ E { Bad k } } } {}
    ^ @ !i E { T k }
}

@ fill inout W w i k → !i E {
    : String b ( string_from `the callee's local string, long enough for the heap` )
    : i x \ ( setw w ( string_data b ) k )
    = w @ W { `literal` }
    ^ @ !i E { T x }
}

@ main → i {
    : ~ W w @ W { `start` }
    ?? ( fill w 1 ) { T _ → {} F _ → {} }
    ( nurl_println . w v )
    ^ 0
}
