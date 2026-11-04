// foreach_element_copy_assigned_to_an_outer_binding: a copy of a foreach element viewing a block-local line, given to an outer binding.
// Closed: the element a foreach binds holds what the iterated value's elements hold; a copy of it holds that too.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | Family G review: a copy of a foreach element viewing a block-local line, given to an outer binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ last ( Vec Tok ) v → Tok { : ~ Tok r @ Tok { Num 0 } ~ e v { = r ( mem_dup e ) } ^ r }

@ main → i {
    : ~ Tok keep @ Tok { Num 1 }
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : ( Vec Tok ) toks ( vec_new [Tok] )
        ( vec_push [Tok] toks @ Tok { Word ( string_data line ) } )
        = keep ( last toks )
    }
    ( show keep )
    ^ 0
}
