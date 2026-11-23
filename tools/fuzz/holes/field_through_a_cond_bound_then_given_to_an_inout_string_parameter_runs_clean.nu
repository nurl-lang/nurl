// map: §7.6 | A2 | runs-clean | - | AGORA-959: a `:` join reading an inner struct's field, handed to an `inout` String parameter, is the parameter's own copy
// AGORA-959: gen_assign copies it where the join lends and marks the row `ak` (main c4c0f350 refused it)
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ f inout String t → v {
    : P p @ P { ( mk ) 1 }
    : String x . p s
    : y ? > ( string_len t ) 0 . p s ( mk )
    = t y
}

@ main → i {
    : ~ String t ( mk )
    ( f t )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
