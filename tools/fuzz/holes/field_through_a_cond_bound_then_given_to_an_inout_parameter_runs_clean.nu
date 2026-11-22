// map: §7.6 | A2 | runs-clean | - | AGORA-954 guard: a `:` join reading an inner struct's field handed to an `inout` parameter, which codegen copies (main 3f08626b refused it)
// AGORA-954: as AGORA-941's field borrow, but the parameter holds a copy of its own on every path the join lends (gen_assign's `ioc_` fact)
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
