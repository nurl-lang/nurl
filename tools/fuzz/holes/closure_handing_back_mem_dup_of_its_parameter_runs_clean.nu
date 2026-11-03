// closure_handing_back_mem_dup_of_its_parameter_runs_clean: a vec_clone_with closure handing back mem_dup of its parameter.
// Kept: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs. What the copy does not hold is not followed.
// main 836c0e9: rejected (a closure handing back mem_dup of its own parameter was read as a capture); now runs clean.
// map: §7.5 | A2 | runs-clean | - | agora #368: a vec_clone_with closure handing back mem_dup of its parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/deque.nu`

: | Tok { Word s Num i Bad String }

@ main → i {
    : String b ( string_from `a string long enough for a heap buffer` )
    : ( Vec Tok ) t ( vec_new [Tok] )
    ( vec_push [Tok] t @ Tok { Word ( string_data b ) } )
    ( vec_push [Tok] t @ Tok { Word ( string_data b ) } )
    ( vec_push [Tok] t @ Tok { Word ( string_data b ) } )
    : ?Tok p1 ( vec_pop [Tok] t )
    : ?Tok p2 ( vec_remove [Tok] t 0 )
    : ?Tok p3 ( vec_get [Tok] t 0 )
    : ?Tok p4 ( vec_replace [Tok] t 0 @ Tok { Num 1 } )
    : ( Vec Tok ) m3 ( vec_clone_with [Tok] t \ Tok x → Tok { ^ ( mem_dup x ) } )
    : ( Vec Tok ) m5 ( vec_clone [Tok] t )
    : ( Deque Tok ) d ( deque_new [Tok] )
    ( deque_push_back [Tok] d @ Tok { Word ( string_data b ) } )
    : ?Tok q1 ( deque_pop_front [Tok] d )
    : ( Deque Tok ) d2 ( Deque_clone [Tok] d )
    ^ 0
}
