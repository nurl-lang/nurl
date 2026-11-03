// enum_literal_viewing_a_param_returned: an enum literal whose payload views a String parameter handed back, pushed out past the String.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #442: an enum literal whose payload views a String parameter handed back, pushed out past the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ mk String line → Tok { ^ @ Tok { Word ( string_data line ) } }

@ main → i {
    : ( Vec Tok ) toks ( vec_new [Tok] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        ( vec_push [Tok] toks ( mk line ) )
    }
    ( show ( vec_at [Tok] toks 0 ) )
    ^ 0
}
