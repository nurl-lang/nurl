// enum_result_viewing_a_temporary_argument_in_a_loop: the in-statement form, in a loop.
// map: §1 | A2 | runs-clean | - | agora #464: ( show ( mk ( string_from … ) ) ) each round of a loop (UAF on main); the temporary lives to its statement's end, and is released once per round
$ `stdlib/core/string.nu`

: | Tok { Word s Num i Bad String }
: W { s w String b }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ mk String line → Tok { ^ @ Tok { Word ( string_data line ) } }

@ mkw String line → W { ^ @ W { ( string_data line ) ( string_from `own` ) } }

@ fresh String line → Tok { ^ @ Tok { Bad ( string_from `fresh string long enough for heap` ) } }

@ lit String line → Tok { ^ @ Tok { Word `a literal` } }

@ num String line → Tok { ^ @ Tok { Num ( string_len line ) } }

@ main → i { : ~ i k 0 ~ < k 3 { ( show ( mk ( string_from `hello world, long enough for a heap buffer` ) ) ) = k + k 1 } ^ 0 }
