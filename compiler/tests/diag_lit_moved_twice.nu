// A binding moved into one field of a literal and handed to a consuming
// call in another: two owners of one String, the second release a double
// free (tools/fuzz/holes h205).
$ `stdlib/core/string.nu`

: Q { String a i n }

@ eat sink String x → i { ^ ( string_len x ) }

@ mk → Q {
    : String t ( string_from `def` )
    ^ @ Q { t ( eat t ) }
}

@ main → i { : Q q ( mk ) ^ . q n }
