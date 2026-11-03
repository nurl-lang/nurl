// mem_dup_of_a_join_of_token_literals_kept_past_its_line: mem_dup of a join of token literals viewing a block-local line.
// Closed: a copy of a view is the same view: a literal's view field copied whole (`mem_dup`, a callee answered `%k`, a `%K.H` row) points where the field does; only a callee copying the elements of a view it is given (vcopies, a container view parameter) holds what those elements view.
// main 836c0e9: rejected (a guard: family G's first head accepted it).
// map: §2.13 | A2 | rejected | - | Family G review: mem_dup of a join of token literals viewing a block-local line
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ main → i {
    : ~ Tok keep @ Tok { Num 1 }
    : i k 3
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        = keep ( mem_dup ? > k 1 @ Tok { Word ( string_data line ) } @ Tok { Num 2 } )
    }
    ?? keep { Word w → ( nurl_println w ) Num n → {} Bad b → {} }
    ^ 0
}
