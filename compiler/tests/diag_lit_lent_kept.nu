// A returned literal keeps a field lent from a binding that another field
// moves in: the result would own one String twice.
$ `stdlib/core/string.nu`

: Two { String a String b }

@ same String x → String { ^ x }

@ mk → Two {
    : String t ( string_from `def` )
    ^ @ Two { t ( same t ) }
}

@ main → i { : Two w ( mk ) ^ ( string_len . w b ) }
