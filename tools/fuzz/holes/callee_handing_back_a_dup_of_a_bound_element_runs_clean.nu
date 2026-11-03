// callee_handing_back_a_dup_of_a_bound_element_runs_clean: a function binds an element of its ( Vec Tok ) parameter and hands back mem_dup of it; the copy outlives the token Vec.
// Kept: a copy of a part of an argument — an element or a field handle, a slice of it — holds what that part holds, not the storage it is in.
// main 836c0e9: rejected (the copy was read as a view of the token Vec); now runs clean.
// map: §2.8 | A2 | runs-clean | - | Family G review: a function binds an element of its ( Vec Tok ) parameter and hands back mem_dup of it; the copy outlives the token Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ first_tok ( Vec Tok ) toks → Tok {
    : Tok t ( vec_at [Tok] toks 0 )
    ^ ( mem_dup t )
}

@ main → i {
    : String line ( string_from `hello world, long enough for a heap buffer` )
    : ~ Tok keep @ Tok { Num 0 }
    {
        : ( Vec Tok ) toks ( vec_new [Tok] )
        ( vec_push [Tok] toks @ Tok { Word ( string_data line ) } )
        = keep ( first_tok toks )
    }
    ( show keep )
    ^ 0
}
