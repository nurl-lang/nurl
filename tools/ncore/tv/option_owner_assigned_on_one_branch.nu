$ `stdlib/core/string.nu`

@ eat sink ? String x → i { ^ 1 }

@ f i n → i {
    : ~ ? String v @ ?String { T ( string_from `the first owner string, long enough for the heap` ) }
    : ~ i k 2
    ? > n 2 { = k ( eat v ) } {}
    ^ + k n
}

@ main → i { ^ + ( f 1 ) ( f 5 ) }
