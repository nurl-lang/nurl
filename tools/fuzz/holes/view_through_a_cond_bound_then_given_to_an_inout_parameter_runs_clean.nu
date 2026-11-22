// map: §7.6 | A2 | runs-clean | - | AGORA-954 guard: a `:` join of a field viewer handed to an `inout` parameter, which codegen copies where the join lends
// AGORA-954: the parameter holds a copy of its own on every path the join does not own its value (gen_assign's `ioc_` fact), so it is no borrow of the struct
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ f inout String t → v {
    : P p @ P { ( mk ) 1 }
    : String x . p s
    : y ? > ( string_len t ) 0 x ( mk )
    = t y
}

@ main → i {
    : ~ String t ( mk )
    ( f t )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
