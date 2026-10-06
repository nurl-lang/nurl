// H28: a view handed to a user function that keeps it in a struct; the String is freed; the struct is read.
$ `stdlib/core/string.nu`

: Bag { ( Vec s ) items }

@ put Bag b s v → v { ( vec_push [s] . b items v ) }

@ main → i {
    : Bag b @ Bag { ( vec_new [s] ) }
    : String t ( string_from `a heap string whose view outlives it, long enough` )
    ( put b ( string_data t ) )
    ( string_free t )
    ?? ( vec_get [s] . b items 0 ) { T v → { ( nurl_println v ) } F → {} }
    ^ 0
}
