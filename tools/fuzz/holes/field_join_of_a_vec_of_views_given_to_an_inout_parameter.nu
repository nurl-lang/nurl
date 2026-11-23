// map: §7.6 | A2 | rejected | - | AGORA-959 guard: a field join holding a Vec of views handed to an `inout` parameter stays refused, the copy is shallow
// AGORA-959: cloneif copies the Vec but not what its views point at; the caller-storage rule refuses it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { ( Vec s ) w i n }

@ f inout ( Vec s ) t b c → v {
    : String y ( string_from `hello world, long enough for a heap buffer` )
    : ~ ( Vec s ) w ( vec_new [s] )
    ( vec_push [s] w ( string_data y ) )
    : P p @ P { w 1 }
    : z ? c . p w ( vec_new [s] )
    = t z
}

@ main → i {
    : ~ ( Vec s ) t ( vec_new [s] )
    ( f t T )
    ( nurl_println_int ( vec_len [s] t ) )
    ^ 0
}
