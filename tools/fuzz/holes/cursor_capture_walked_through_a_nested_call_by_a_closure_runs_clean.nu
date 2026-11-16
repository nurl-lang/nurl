// cursor_capture_walked_through_a_nested_call_by_a_closure_runs_clean: `= cur ( nid ( first cur ) )`: a lend of the capture itself, no copy - a push through cur reaches the list (prints 1)
// Closed: a capture by pointer given a lend of what dies with the closure (a local or a parameter of it) is given a copy it owns, as an `inout` parameter is (gen_assign; agora #872).
// main 525613db: runs clean (guard: cursor semantics).
// map: §7.4 | A2 | runs-clean | - | AGORA-872: `= cur ( nid ( first cur ) )`: a lend of the capture itself, no copy - a push through cur reaches the list (prints 1)
$ `stdlib/core/vec.nu`

: N { i v ( Vec N ) kids }

@ nid ( Vec N ) a → ( Vec N ) { ^ a }

@ first ( Vec N ) ks → ( Vec N ) { ^ . ( vec_at [N] ks 0 ) kids }

@ main → i {
    : ( Vec N ) l2 ( vec_new [N] )
    : ( Vec N ) l1 ( vec_new [N] )
    ( vec_push [N] l1 @ N { 1 l2 } )
    : ~ ( Vec N ) cur l1
    : ~ ( @ v ) step \ → v { = cur ( nid ( first cur ) ) }
    ( step )
    ( vec_push [N] cur @ N { 9 ( vec_new [N] ) } )
    ( nurl_println_int ( vec_len [N] . ( vec_at [N] l1 0 ) kids ) )
    ^ 0
}
