// H29: a view handed to a user function defined LATER that keeps it; the owner is dropped at the end of its block; the container is read.
$ `stdlib/core/string.nu`

: Bag { ( Vec s ) items }

@ main → i {
    : Bag b @ Bag { ( vec_new [s] ) }
    ? > ( nurl_str_len `ab` ) 1 {
        : String t ( string_from `a heap string whose view outlives it, long enough` )
        ( put b ( string_data t ) )
    } {}
    ?? ( vec_get [s] . b items 0 ) { T v → { ( nurl_println v ) } F → {} }
    ^ 0
}

@ put Bag b s v → v { ( vec_push [s] . b items v ) }
