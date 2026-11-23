// map: §7.6 | A2 | runs-clean | - | AGORA-959: a field join handed to an `inout` parameter stays readable where it lent, it was copied
// AGORA-959: the `ak` handover leaves a lending source as it was; where it owned, it moved
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ f inout String t → v {
    : P p @ P { ( mk ) 1 }
    : y ? > ( string_len t ) 0 . p s ( mk )
    = t y
    ( nurl_println_int ( string_len . p s ) )
}

@ main → i {
    : ~ String t ( mk )
    ( f t )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
