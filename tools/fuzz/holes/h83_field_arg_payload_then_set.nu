// H83: the payload of vec_get through a field argument, in a function with nothing pending; the element is replaced; the payload is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items }

@ main → i {
    : Bag b @ Bag { ( vec_new [String] ) }
    ( vec_push [String] . b items ( string_from `a long element string on the heap` ) )
    ?? ( vec_get [String] . b items 0 ) {
        T e → {
            ( vec_set [String] . b items 0 ( string_from `replacement` ) )
            ( nurl_println_int ( string_len e ) )
        }
        F → {}
    }
    ^ 0
}
