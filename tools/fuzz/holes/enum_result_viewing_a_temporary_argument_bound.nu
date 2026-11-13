// enum_result_viewing_a_temporary_argument_bound: an enum result holding a view of its temporary argument, bound past the statement.
// map: §1 | A2 | rejected | - | agora #464: : Tok t ( mk ( string_from … ) ), mk handing back Tok { Word ( string_data line ) }: the temporary was dropped after the call while t viewed it (UAF on main); a temporary the result may view, kept past its statement, is refused
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ mk String line → Tok { ^ @ Tok { Word ( string_data line ) } }

@ main → i {
    : Tok t ( mk ( string_from `hello world, long enough for a heap buffer` ) )
    ( show t )
    ^ 0
}
