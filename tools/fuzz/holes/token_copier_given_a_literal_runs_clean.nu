// token_copier_given_a_literal_runs_clean: the same callee given a literal, the line outliving the Vec.
// Kept: a copy of a view is the same view: a literal's view field copied whole (`mem_dup`, a callee answered `%k`, a `%K.H` row) points where the field does; only a callee copying the elements of a view it is given (vcopies, a container view parameter) holds what those elements view.
// main 836c0e9: accepted; ran clean.
// map: §2.7 | A2 | runs-clean | - | Family G review: the same callee given a literal, the line outliving the Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ keep inout ( Vec Tok ) d Tok t → v { ( vec_push [Tok] d ( mem_dup t ) ) }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : String line ( string_from `hello world, long enough for a heap buffer` )
    : ~ ( Vec Tok ) ws ( vec_new [Tok] )
    {
        ( keep ws @ Tok { Word ( string_data line ) } )
    }
    ( show ( vec_at [Tok] ws 0 ) )
    ^ 0
}
