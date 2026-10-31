// field_replaced_on_one_branch_under_its_reader: agora #265 — a field replaced on one branch of a `?` under a binding read out of it, an `Arc` first.
// Closed: a binding read out of a field that a store replacing the field handed the old value owns it: the hand-over compares a struct by its first field with an identity (past an `Arc`; an `Arc`-only struct by its control block, while the binding owns nothing yet), and what takes the binding on — a literal, a store, a `sink`, the return — moves its value and leaves the field's new one in place (mem_handle_key, __fview_key, __field_holds_cond, __fview_lent; agora #265).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #265: a field replaced on one branch under its reader (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/arc.nu`

: Inner { ( Arc ( Vec i ) ) a ( Vec i ) v }
: Outer { Inner cur }

@ take inout Outer o i k → Inner {
    : Inner got . o cur
    ? > k 0 { = . o cur @ Inner { ( arc_new [( Vec i )] ( vec_new [i] ) ) ( vec_new [i] ) } } {}
    ^ got
}

@ main → i {
    : ~ Outer o @ Outer { @ Inner { ( arc_new [( Vec i )] ( vec_new [i] ) ) ( vec_new [i] ) } }
    ( vec_push [i] . . o cur v 7 )
    : Inner g ( take o 1 )
    ( nurl_println_int ( vec_len [i] . g v ) )
    : Inner h ( take o 0 )
    ( nurl_println_int ( vec_len [i] . h v ) )
    ^ 0
}
