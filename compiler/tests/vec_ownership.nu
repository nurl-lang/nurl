// Test: Vec[String] ownership — caller iterates and string_free's each
// element before vec_free, since Vec does NOT auto-drop elements.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )

    // Build three owned strings and push them.
    : String a ( string_new )
    ( string_push_str a `alpha` )
    : String b ( string_new )
    ( string_push_str b `beta` )
    : String c ( string_new )
    ( string_push_str c `gamma` )
    ( vec_push [String] v a )
    ( vec_push [String] v b )
    ( vec_push [String] v c )

    ( nurl_print `len=` )
    ( nurl_print ( nurl_str_int ( vec_len [String] v ) ) )
    ( nurl_print `\n` )

    // Iterate via vec_get and print each element's borrowed buffer.
    : ~ i i 0
    ~ < i ( vec_len [String] v ) {
        : ?String got ( vec_get [String] v i )
        ?? got {
            T s → { ( nurl_print ( string_data s ) ) ( nurl_print `\n` ) }
            F → ( nurl_print `??\n` )
        }
        = i + i 1
    }

    // Element cleanup: walk the Vec and free each String, then free the Vec.
    = i 0
    ~ < i ( vec_len [String] v ) {
        : ?String got ( vec_get [String] v i )
        ?? got {
            T s → ( string_free s )
            F → {}
        }
        = i + i 1
    }
    ( vec_free [String] v )

    ( nurl_print `done\n` )
    ^ 0
}
