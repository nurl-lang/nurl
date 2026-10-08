// H94: a view of a Vec element's buffer; the element grows through its borrow; the view is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `abc` ) )
    : ?String o ( vec_get [String] xs 0 )
    ?? o {
        T e → {
            : s k ( string_data e )
            : ~ i j 0
            ~ < j 50 { ( string_push_str e `grow the element's own buffer` ) = j + j 1 }
            ( nurl_println k )
        }
        F → {}
    }
    ^ 0
}
