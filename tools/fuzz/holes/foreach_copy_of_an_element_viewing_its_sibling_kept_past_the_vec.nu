// foreach_copy_of_an_element_viewing_its_sibling_kept_past_the_vec: a foreach copies the elements of a Vec whose second token views the first token's String; kept past the Vec.
// Closed: a container whose elements view its own storage — an element viewing a sibling's String, a field viewing another field — holds views of itself (`vsv_`, recorded where its dependency on itself is dropped, and carried along when such a value is moved in whole): a copy of a part of it holds them, and outlives it no longer.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | Family G review: a foreach copies the elements of a Vec whose second token views the first token's String; kept past the Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Bad String }

@ main → i {
    : ~ Tok keep @ Tok { Word `` }
    {
        : ( Vec Tok ) toks ( vec_new [Tok] )
        ( vec_push [Tok] toks @ Tok { Bad ( string_from `an owned string inside the token vec itself` ) } )
        ?? ( vec_at [Tok] toks 0 ) { Bad b → { ( vec_push [Tok] toks @ Tok { Word ( string_data b ) } ) } Word x → {} }
        ~ t toks { = keep ( mem_dup t ) }
    }
    ?? keep { Word w → { ( nurl_println w ) } Bad b → {} }
    ^ 0
}
