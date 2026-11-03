// payload_copy_of_an_element_viewing_its_sibling_kept_past_the_vec: mem_dup of a token payload matched out of an element that views its sibling's String, kept past the Vec.
// Closed: a container whose elements view its own storage — an element viewing a sibling's String, a field viewing another field — holds views of itself (`vsv_`, recorded where its dependency on itself is dropped, and carried along when such a value is moved in whole): a copy of a part of it holds them, and outlives it no longer.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | Family G review: mem_dup of a token payload matched out of an element that views its sibling's String, kept past the Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }
: | Slot { Full Tok Vacant i }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ~ Tok keep @ Tok { Num 0 }
    {
        : ( Vec Slot ) slots ( vec_new [Slot] )
        ( vec_push [Slot] slots @ Slot { Full @ Tok { Bad ( string_from `an owned string inside the slot vec itself` ) } } )
        ?? ( vec_at [Slot] slots 0 ) { Full tk → { ?? tk { Bad b → { ( vec_push [Slot] slots @ Slot { Full @ Tok { Word ( string_data b ) } } ) } Word x → {} Num n → {} } } Vacant e → {} }
        ?? ( vec_at [Slot] slots 1 ) { Full tk → { = keep ( mem_dup tk ) } Vacant e → {} }
    }
    ( show keep )
    ^ 0
}
