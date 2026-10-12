// A binding moved into one field of a literal and handed, in another, to
// a callee that keeps it — decided at module end, since `wrap` is defined
// below (tools/fuzz/holes h205).
$ `stdlib/core/string.nu`

: Holder { String h }
: Two { String a Holder b }

@ mk → Two {
    : String t ( string_from `seven` )
    ^ @ Two { t ( wrap t ) }
}

@ wrap String x → Holder { ^ @ Holder { x } }

@ main → i { : Two w ( mk ) ^ ( string_len . w a ) }
