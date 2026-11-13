// enum_result_viewing_a_temporary_argument_in_its_statement: an enum result holding a view of its temporary argument, read by a call in the same statement.
// map: §1 | A2 | runs-clean | - | agora #464: ( show ( mk ( string_from … ) ) ): the temporary was dropped right after mk, before show read the view (UAF on main); it now lives to the statement's end
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ mk String line → Tok { ^ @ Tok { Word ( string_data line ) } }

@ main → i {
    ( show ( mk ( string_from `hello world, long enough for a heap buffer` ) ) )
    ^ 0
}
