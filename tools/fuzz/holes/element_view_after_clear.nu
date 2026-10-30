// element_view_after_clear: a view of a Vec element's buffer; the Vec drops its elements; the view is read.
// map: RhsT.pop | A1 | rejected | h95 | view of element's buffer; Vec cleared; view read
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough for the heap` ) )
    : ?String o ( vec_get [String] xs 0 )
    ?? o {
        T e → {
            : s k ( string_data e )
            ( vec_clear [String] xs )
            ( nurl_println k )
        }
        F → {}
    }
    ^ 0
}
