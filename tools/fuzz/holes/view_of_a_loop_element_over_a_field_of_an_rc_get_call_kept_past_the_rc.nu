// view_of_a_loop_element_over_a_field_of_an_rc_get_call_kept_past_the_rc: agora #471 — `~ x . ( rc_get [B] r ) items` pushes views of `x` into `ws`; the Rc ends at its block's end and `ws` is read after
// Closed: a container path rooted at a call is a part of what the call lends: the loop element's `fe_` names the bindings the call lends (bck_sx_hroots), not an id its text read as (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a view of a loop element over a field of an rc_get call, kept past the Rc
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: B { ( Vec String ) items i n }

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string in an Rc'd struct's Vec, freed with the last Rc` ) )
        : ( Rc B ) r ( rc_new [B] @ B { t 1 } )
        ~ x . ( rc_get [B] r ) items { ( vec_push [s] ws ( string_data x ) ) }
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
