// outer_string_copy_of_an_element_runs_clean: a view of toks[0]'s String given to an outer `: ~ s` (a copy of its bytes), pushed as a token, the token copied past toks.
// Kept: a view given to a `: ~ s` binding is a copy of its bytes the binding owns: the token pushed holds no view of the Vec, and its copy outlives it.
// main 836c0e9: accepted; ran clean.
// map: §2.13 | A2 | runs-clean | - | Family G review: a view of toks[0]'s String given to an outer `: ~ s` (a copy of its bytes), pushed as a token, the token copied past toks
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ~ Tok keep @ Tok { Num 0 }
    : ~ s w ``
    {
        : ( Vec Tok ) toks ( vec_new [Tok] )
        ( vec_push [Tok] toks @ Tok { Bad ( string_from `an owned string inside the token vec itself` ) } )
        : Tok first ( vec_at [Tok] toks 0 )
        ?? first { Bad b → { = w ( string_data b ) } Word x → {} Num n → {} }
        ( vec_push [Tok] toks @ Tok { Word w } )
        : Tok t ( vec_at [Tok] toks 1 )
        = keep ( mem_dup t )
    }
    ( show keep )
    ^ 0
}
