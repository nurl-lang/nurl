// A returned literal keeps a field lent from a binding that another field
// moves in: the result would own one String twice. (In a function the
// lent field is copied — agora #189, lit_moved_and_lent_copied_ok; a
// closure's result is judged as it is, and refused.)
$ `stdlib/core/string.nu`

: Two { String a String b }

@ same String x → String { ^ x }

@ main → i {
    : ( @ Two ) f \ → Two {
        : String t ( string_from `def` )
        ^ @ Two { t ( same t ) }
    }
    : Two w ( f )
    ^ ( string_len . w b )
}
