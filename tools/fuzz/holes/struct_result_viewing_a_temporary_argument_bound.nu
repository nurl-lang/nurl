// struct_result_viewing_a_temporary_argument_bound: a struct result of a view and a String, the view of its temporary argument, bound past the statement.
// map: §1 | A2 | rejected | - | agora #464: : W v ( mkw ( string_from … ) ), W { s w String b } given ( string_data line ): the temporary was dropped after the call while v.w viewed it (UAF on main); refused as the enum form
$ `stdlib/core/string.nu`

: | Tok { Word s Num i Bad String }
: W { s w String b }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ mk String line → Tok { ^ @ Tok { Word ( string_data line ) } }

@ mkw String line → W { ^ @ W { ( string_data line ) ( string_from `own` ) } }

@ fresh String line → Tok { ^ @ Tok { Bad ( string_from `fresh string long enough for heap` ) } }

@ lit String line → Tok { ^ @ Tok { Word `a literal` } }

@ num String line → Tok { ^ @ Tok { Num ( string_len line ) } }

@ main → i { : W v ( mkw ( string_from `hello world, long enough for a heap buffer` ) ) ( nurl_println . v w ) ^ 0 }
