// H93: a view of a String is kept; the String moves into an arena; the arena drops its elements; the view is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec s ) views ( vec_new [s] )
    : ( Vec String ) arena ( vec_new [String] )
    : String line ( string_from `a heap line long enough to be its own allocation` )
    ( vec_push [s] views ( string_data line ) )
    ( vec_push [String] arena line )
    ( vec_clear [String] arena )
    ?? ( vec_get [s] views 0 ) { T v → { ( nurl_println v ) } F → {} }
    ^ 0
}
