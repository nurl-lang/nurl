// H90: the payload of a borrowed option binding (a vec_get result) is read after its Vec is freed.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `a long string element on the heap` ) )
    : ?String o ( vec_get [String] xs 0 )
    ?? o {
        T e → {
            ( vec_free [String] xs )
            ( nurl_println_int ( string_len e ) )
        }
        F → {}
    }
    ^ 0
}
