// field_path_borrows.nu — a borrow taken through a field argument borrows
// that field, not the whole struct: changing ANOTHER field leaves it valid.
//
// `( vec_at [String] . b items 0 )` lends an element of `. b items`. Writing
// a scalar field, replacing or clearing a different Vec field, or changing a
// sibling of a nested path does not touch that element, so the borrow stays
// readable. (Changing `. b items` itself, a field holding it, or handing the
// whole of `b` to a mutator ends it — tools/fuzz/holes h82-h88.)

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items ( Vec String ) other i count }
: Outer { Bag b Bag c }

@ fresh String first → Bag {
    : Bag b @ Bag { ( vec_new [String] ) ( vec_new [String] ) 0 }
    ( vec_push [String] . b items first )
    ( vec_push [String] . b other ( string_from `other` ) )
    ^ b
}

@ main → i {
    : ~ Bag b ( fresh ( string_from `items element` ) )
    : String e ( vec_at [String] . b items 0 )
    = . b count + . b count 1
    ( vec_set [String] . b other 0 ( string_from `replaced` ) )
    ( vec_clear [String] . b other )
    = . b other ( vec_new [String] )
    ( nurl_println ( string_data e ) )

    : Outer o @ Outer { ( fresh ( string_from `nested element` ) ) ( fresh ( string_from `sibling` ) ) }
    : String n ( vec_at [String] . . o b items 0 )
    ( vec_clear [String] . . o c items )
    ( vec_clear [String] . . o b other )
    ( nurl_println ( string_data n ) )

    ?? ( vec_get [String] . b items 0 ) {
        T p → {
            ( vec_push [String] . b other ( string_from `pushed` ) )
            ( nurl_println ( string_data p ) )
        }
        F → {}
    }
    ^ 0
}
