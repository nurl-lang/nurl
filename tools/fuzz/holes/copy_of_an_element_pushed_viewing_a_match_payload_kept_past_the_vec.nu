// copy_of_an_element_pushed_viewing_a_match_payload_kept_past_the_vec: inside a match on toks[0], a token viewing its payload pushed into toks; mem_dup of toks[1] kept past toks.
// Closed: a container whose elements view its own storage — an element viewing a sibling's String, a field viewing another field — holds views of itself (`vsv_`, recorded where its dependency on itself is dropped, and carried along when such a value is moved in whole): a copy of a part of it holds them, and outlives it no longer.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | Family G review: inside a match on toks[0], a token viewing its payload pushed into toks; mem_dup of toks[1] kept past toks
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ~ Tok keep @ Tok { Num 0 }
    {
        : ( Vec Tok ) toks ( vec_new [Tok] )
        ( vec_push [Tok] toks @ Tok { Bad ( string_from `an owned string inside the token vec itself` ) } )
        ?? ( vec_at [Tok] toks 0 ) { Bad b → { ( vec_push [Tok] toks @ Tok { Word ( string_data b ) } ) } Word x → {} Num n → {} }
        : Tok t ( vec_at [Tok] toks 1 )
        = keep ( mem_dup t )
    }
    ( show keep )
    ^ 0
}
