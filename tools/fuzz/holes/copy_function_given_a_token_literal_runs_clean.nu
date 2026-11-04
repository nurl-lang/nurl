// copy_function_given_a_token_literal_runs_clean: the same function given a literal, the line outliving the copy.
// Kept: a copy of a view is the same view: a literal's view field copied whole (`mem_dup`, a callee answered `%k`, a `%K.H` row) points where the field does; only a callee copying the elements of a view it is given (vcopies, a container view parameter) holds what those elements view.
// main 836c0e9: accepted; ran clean.
// map: §2.13 | A2 | runs-clean | - | Family G review: the same function given a literal, the line outliving the copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ dup_tok Tok t → Tok { ^ ( mem_dup t ) }

@ main → i {
    : String line ( string_from `hello world, long enough for a heap buffer` )
    : ~ Tok keep @ Tok { Num 1 }
    {
        = keep ( dup_tok @ Tok { Word ( string_data line ) } )
    }
    ?? keep { Word w → ( nurl_println w ) Num n → {} Bad b → {} }
    ^ 0
}
