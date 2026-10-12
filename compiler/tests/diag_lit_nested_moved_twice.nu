// A binding moved into one field of a literal and into a literal nested
// in another field: two owners of one String (tools/fuzz/holes h206).
$ `stdlib/core/string.nu`

: Holder { String h }
: Two { String a Holder b }

@ mk → Two {
    : String t ( string_from `seven` )
    ^ @ Two { t @ Holder { t } }
}

@ main → i { : Two w ( mk ) ^ ( string_len . w a ) }
