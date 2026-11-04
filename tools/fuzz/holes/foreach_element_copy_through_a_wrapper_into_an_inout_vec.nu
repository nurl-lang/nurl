// foreach_element_copy_through_a_wrapper_into_an_inout_vec: a copy of a foreach element pushed by a wrapper into an inout Vec.
// Closed: the element a foreach binds holds what the iterated value's elements hold; a copy of it holds that too.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | Family G review: a copy of a foreach element pushed by a wrapper into an inout Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ ext inout ( Vec Tok ) d ( Vec Tok ) t → v { ~ e t { ( vec_push [Tok] d ( mem_dup e ) ) } }

@ main → i {
    : ~ ( Vec Tok ) outer ( vec_new [Tok] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : ( Vec Tok ) src ( vec_new [Tok] )
        ( vec_push [Tok] src @ Tok { Word ( string_data line ) } )
        ( ext outer src )
    }
    ( show ( vec_at [Tok] outer 0 ) )
    ^ 0
}
