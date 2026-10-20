// foreach_field_path.nu — `~ x . obj field { … }` iterates a field.
//
// A foreach was told from a while loop by `~ name name`; with the values
// in a field the second token is `.`, and `~ e . m items { … }` read as a
// while loop on `e` ("use of undefined identifier"). A while condition is
// one expression, so a name followed by a member path is never one: it is
// a foreach. Mutating that field inside the body is refused
// (borrow_foreach_field_mutated.nu); another field of the same struct is
// not.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Item { String name i weight }

: Bag {
    ( Vec Item ) items
    ( Vec i ) extra
}

: Outer { Bag bag }

@ total Bag b → i {
    : ~ i n 0
    ~ it . b items { = n + n . it weight }
    ^ n
}

@ main → i {
    : Bag b @ Bag { ( vec_new [Item] ) ( vec_new [i] ) }
    ( vec_push [Item] . b items @ Item { ( string_from `apple` ) 3 } )
    ( vec_push [Item] . b items @ Item { ( string_from `pear` ) 5 } )
    ( vec_push [i] . b extra 7 )
    ( nurl_println ( nurl_str_cat `total ` ( nurl_str_int ( total b ) ) ) )
    : ~ i letters 0
    ~ it . b items { = letters + letters ( string_len . it name ) }
    ( nurl_println ( nurl_str_cat `letters ` ( nurl_str_int letters ) ) )
    // Another field of the struct changes while one is iterated.
    ~ it . b items { ( vec_push [i] . b extra . it weight ) }
    ( nurl_println ( nurl_str_cat `extra ` ( nurl_str_int ( vec_len [i] . b extra ) ) ) )
    : Outer o @ Outer { b }
    : ~ i x 0
    ~ e . . o bag extra { = x + x e }
    ( nurl_println ( nurl_str_cat `nested ` ( nurl_str_int x ) ) )
    ^ 0
}
