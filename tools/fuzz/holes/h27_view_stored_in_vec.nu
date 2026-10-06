// H27: a view pushed into a Vec of views; the String is freed; the view is read.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec s ) views ( vec_new [s] )
    : String t ( string_from `a heap string whose view outlives it, long enough` )
    ( vec_push [s] views ( string_data t ) )
    ( string_free t )
    ?? ( vec_get [s] views 0 ) { T v → { ( nurl_println v ) } F → {} }
    ^ 0
}
