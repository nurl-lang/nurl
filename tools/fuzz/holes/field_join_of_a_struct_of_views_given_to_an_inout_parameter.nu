// map: §7.6 | A2 | rejected | - | AGORA-959 guard: a field join of a struct of views handed to an `inout` parameter stays refused, the copy is shallow
// AGORA-959: cloneif copies the struct but not what its view points at; the caller-storage rule refuses it
$ `stdlib/core/string.nu`

: V { s t }

: P { V v i n }

@ f inout V t b c → v {
    : String st ( string_from `hello world, long enough for a heap buffer` )
    : P p @ P { @ V { ( string_data st ) } 1 }
    : y ? c . p v @ V { `lit` }
    = t y
}

@ main → i {
    : ~ V t @ V { `start` }
    ( f t T )
    ( nurl_println . t t )
    ^ 0
}
