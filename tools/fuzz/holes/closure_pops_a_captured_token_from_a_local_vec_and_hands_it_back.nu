// closure_pops_a_captured_token_from_a_local_vec_and_hands_it_back: a closure literal pushes a captured view-holder into a local Vec, pops it back in a tail `??` without `^`, and hands it back.
// Closed: `bck_sx_name` propagates a capture's `cv_` into the local Vec's `vds_`, `vec_pop`'s option payload inherits those sources, and `__bck_fall_ret_record` records the implicit tail `??` return before `bck_block_exit` so `bck_ret_view_check` refuses it (h220; agora #473).
// main a3be3e7c: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.5 | A2 | rejected | h220 | agora #473: a closure literal pushes a captured view-holder into a local Vec and pops it back as its result
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tok { s w }

@ call0 ( @ Tok ) f → Tok { ^ ( f ) }

@ leak → Tok {
    : String s ( string_from `hello world from freed string buffer on heap` )
    : Tok ct @ Tok { ( string_data s ) }
    ^ ( call0 \ → Tok {
        : ( Vec Tok ) v ( vec_new [Tok] )
        ( vec_push [Tok] v ct )
        ?? ( vec_pop [Tok] v ) {
            T u → u
            F → @ Tok { `ok` }
        }
    } )
}

@ main → i {
    : Tok out ( leak )
    ( nurl_println . out w )
    ^ 0
}
