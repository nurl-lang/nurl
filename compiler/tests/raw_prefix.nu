// raw_prefix.nu — `raw @` (grammar v2.9): an `unsafe` caller vouches for
// what a raw function requires and may call it; `raw : S` seals a struct
// that only `unsafe` code builds; and `raw` stays an ordinary identifier
// everywhere but right before `@` or `:` — even on the line after an
// import, where it could have been read as the import's alias.
$ `stdlib/core/vec.nu`

raw @ first ( Vec i ) v → i {
    : *i p ( vec_data [i] v )
    ^ . p 0
}

raw : Span { i lo i n }

unsafe @ span_new i n → Span { ^ @ Span { 0 n } }

: i raw 3

: Pair { i raw i cooked }

unsafe @ head ( Vec i ) v → i {
    ? == ( vec_len [i] v ) 0 { ^ -1 } {}
    ^ ( first v )
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 42 )
    ( nurl_println_int ( head v ) )
    : Span sp ( span_new 7 )
    ( nurl_println_int . sp n )
    : Pair p @ Pair { raw 4 }
    ( nurl_println_int + . p raw . p cooked )
    ^ 0
}
