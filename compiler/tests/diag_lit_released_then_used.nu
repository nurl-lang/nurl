// One field keeps a view of a String a later field of the same literal
// releases: the view dangles as soon as the literal exists.
$ `stdlib/core/string.nu`

: P { s v i n }

@ eat sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String s ( string_from `abc` )
    : P p @ P { ( string_data s ) ( eat s ) }
    ^ . p n
}
