// `^ # T a`, a cast of a binding to the type it already has, is `^ a`: a
// local is handed over, a parameter copied for the caller. Taken for a
// read through a cast it was lent by nobody — the local's value leaked, a
// String's, a struct's and a slice's alike (agora #545).
$ `stdlib/core/string.nu`

: P { String name i n }

@ get_slice → [i { : [i a [i | 1 2 3] ^ # [i a }
@ get_string → String { : String a ( string_from `a long enough string to be on the heap, one` ) ^ # String a }
@ get_struct → P { : P a @ P { ( string_from `a long enough string to be on the heap, two!` ) 1 } ^ # P a }
@ of_param [i a → [i { ^ # [i a }
@ of_param_s String a → String { ^ # String a }

@ pick b c [i p → [i {
    : [i loc [i | 7 8]
    ? c { ^ # [i loc } {}
    ^ # [i p
}

@ main → i {
    : [i w ( get_slice )
    ~ x w { ( nurl_println ( nurl_str_int x ) ) }
    : String t ( get_string )
    ( nurl_println ( string_data t ) )
    : P u ( get_struct )
    ( nurl_println ( string_data . u name ) )
    ( get_slice )
    ( get_string )
    ( get_struct )
    : [i q [i | 4 5 6]
    : [i w2 ( of_param q )
    ~ x w2 { ( nurl_println ( nurl_str_int x ) ) }
    ~ x q { ( nurl_println ( nurl_str_int x ) ) }
    : String qs ( string_from `a long enough string to be on the heap, q` )
    : String w3 ( of_param_s qs )
    ( nurl_println ( string_data w3 ) )
    ( nurl_println ( string_data qs ) )
    : [i w4 ( pick T q )
    : [i w5 ( pick F q )
    ( nurl_println ( nurl_str_int + . w4 length . w5 length ) )
    : [i w6 # [i q
    ~ x w6 { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
