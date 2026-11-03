// foreach_element_struct_of_views_assigned_out: a foreach element that is a struct of views, given to an outer binding.
// Closed: the element a foreach binds holds what the iterated value's elements hold; a copy of it holds that too.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | Family G review: a foreach element that is a struct of views, given to an outer binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v i n }

@ main → i {
    : ~ W keep @ W { `short` 0 }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec W ) t ( vec_new [W] )
        ( vec_push [W] t @ W { ( string_data b ) 1 } )
        ~ w t { = keep w }
    }
    ( nurl_println . keep v )
    ^ 0
}
