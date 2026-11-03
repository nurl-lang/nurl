// struct_of_a_view_and_an_owner_viewing_a_param_returned: a literal of a view beside an owned field, viewing a String parameter, handed back.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #442: a literal of a view beside an owned field, viewing a String parameter, handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tok { s w String b }

@ show Tok t → v { ( nurl_println . t w ) }

@ mk String line → Tok { ^ @ Tok { ( string_data line ) ( string_from `x` ) } }

@ main → i {
    : ( Vec Tok ) toks ( vec_new [Tok] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        ( vec_push [Tok] toks ( mk line ) )
    }
    ( show ( vec_at [Tok] toks 0 ) )
    ^ 0
}
