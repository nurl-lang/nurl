// closure_hands_back_an_enum_viewing_its_capture: a closure hands back an enum literal whose payload views its capture.
// Closed: a closure may not hand back an owner that holds views of what it captured, as it may not hand back such a view (h220): its caller cannot see what the capture points into (agora #369).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #369: a closure hands back an enum literal whose payload views its capture
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ( Vec Tok ) toks ( vec_new [Tok] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : ( @ Tok ) mk \ → Tok { ^ @ Tok { Word ( string_data line ) } }
        ( vec_push [Tok] toks ( mk ) )
    }
    ( show ( vec_at [Tok] toks 0 ) )
    ^ 0
}
