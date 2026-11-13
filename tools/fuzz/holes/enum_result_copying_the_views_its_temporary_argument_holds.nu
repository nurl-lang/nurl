// enum_result_copying_the_views_its_temporary_argument_holds: a result holding a copy of a view its temporary argument holds (the walk's `%k`, as nurldb's pool_new over a mem_dup'd Wal).
// map: §1 | A2 | runs-clean | - | agora #464: copyw W w → Tok { Word . w w }: the result copies a view the temporary holds (a literal), not one of its storage; the temporary is still released right after the call, bound or in its statement
$ `stdlib/core/string.nu`

: | Tok { Word s Num i Bad String }
: W { s w String b }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ mkw2 → W { ^ @ W { `a literal the result copies` ( string_from `an owned string long enough for heap` ) } }

@ copyw W w → Tok { ^ @ Tok { Word . w w } }

@ main → i {
    : Tok t ( copyw ( mkw2 ) )
    ( show t )
    : ~ i k 0 ~ < k 3 { ( show ( copyw ( mkw2 ) ) ) = k + k 1 }
    ^ 0
}
