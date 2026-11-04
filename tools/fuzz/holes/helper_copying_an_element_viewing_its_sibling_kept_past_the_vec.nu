// helper_copying_an_element_viewing_its_sibling_kept_past_the_vec: a helper copying an element of a token Vec whose second token views the first's String into an inout holder, read past the Vec.
// Closed: a container whose elements view its own storage — an element viewing a sibling's String, a field viewing another field — holds views of itself (`vsv_`, recorded where its dependency on itself is dropped, and carried along when such a value is moved in whole): a copy of a part of it holds them, and outlives it no longer.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | Family G review: a helper copying an element of a token Vec whose second token views the first's String into an inout holder, read past the Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ keep_last inout ( Vec Tok ) summary ( Vec Tok ) toks → v {
    ? > ( vec_len [Tok] toks ) 0 {
        : Tok t ( vec_at [Tok] toks - ( vec_len [Tok] toks ) 1 )
        ( vec_push [Tok] summary ( mem_dup t ) )
    } {}
}

@ main → i {
    : ~ ( Vec Tok ) summary ( vec_new [Tok] )
    {
        : ( Vec Tok ) toks ( vec_new [Tok] )
        ( vec_push [Tok] toks @ Tok { Bad ( string_from `an owned string inside the token vec itself` ) } )
        ?? ( vec_at [Tok] toks 0 ) { Bad b → { ( vec_push [Tok] toks @ Tok { Word ( string_data b ) } ) } Word x → {} Num n → {} }
        ( keep_last summary toks )
    }
    ( show ( vec_at [Tok] summary 0 ) )
    ^ 0
}
