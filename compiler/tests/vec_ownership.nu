// Test: Vec[String] ownership — the Vec owns its elements: vec_free drops
// each String with it. An element read with vec_get is a borrow, which the
// program never releases by its own name.
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

    // Cleanup: the Vec drops each String with it.
    ( vec_free [String] v )

    ( nurl_print `done\n` )
    ^ 0
}
