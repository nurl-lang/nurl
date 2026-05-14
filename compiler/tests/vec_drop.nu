// Test: stdlib/core/vec.nu — vec_free_with drops every owned element
// before releasing the buffer. Closes the Vec[String] memory-leak trap
// that bare vec_free leaves open.
//
// Pattern mirrors HashMap's hash/eq closures: wrap the @-function
// `string_free` in a `\`-closure at the call site, since NURL passes
// closure values (16-byte fn-ptr + env), not raw @-function names,
// to higher-order parameters.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )

    // Build five owned strings and push them. Without vec_free_with each
    // would leak its sb buffer.
    : String a ( string_new )
    ( string_push_str a `alpha` )
    : String b ( string_new )
    ( string_push_str b `beta` )
    : String c ( string_new )
    ( string_push_str c `gamma` )
    : String d ( string_new )
    ( string_push_str d `delta` )
    : String e ( string_new )
    ( string_push_str e `epsilon` )
    ( vec_push [String] v a )
    ( vec_push [String] v b )
    ( vec_push [String] v c )
    ( vec_push [String] v d )
    ( vec_push [String] v e )

    ( nurl_print `len=` )
    ( nurl_print ( nurl_str_int ( vec_len [String] v ) ) )
    ( nurl_print `\n` )

    // Print each element via vec_each.
    : ( @ v String ) show \ String elt → v {
        ( nurl_print ( string_data elt ) )
        ( nurl_print ` ` )
    }
    ( vec_each [String] v show )
    ( nurl_print `\n` )

    // Drop every element + free the Vec in one call. Closure wrapping
    // the @-function `string_free` — same pattern as hashmap_generic.nu.
    : ( @ v String ) drop \ String elt → v { ( string_free elt ) }
    ( vec_free_with [String] v drop )

    // Second case: empty Vec[String] — drop closure must NOT be called.
    : ( Vec String ) empty ( vec_new [String] )
    ( vec_free_with [String] empty drop )

    ( nurl_print `done\n` )
    ^ 0
}
