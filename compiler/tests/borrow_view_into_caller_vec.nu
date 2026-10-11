// A view of a string this function releases, stored into storage its
// caller holds — the caller's ( Vec s ) handed in, an alias of it, or a
// `sink s` parameter (released on the way out like a local) — would be read
// by the caller after it is freed: each store is an error naming both.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ add_local ( Vec s ) v → v {
    : s x ( nurl_str_cat `ab` `cd` )
    ( vec_push [s] v x )
}

@ add_alias ( Vec s ) v → v {
    : s x ( nurl_str_cat `ef` `gh` )
    : ( Vec s ) w v
    ( vec_push [s] w x )
}

@ add_sink ( Vec s ) v sink s x → v { ( vec_push [s] v x ) }

@ main → i {
    : ( Vec s ) v ( vec_new [s] )
    ( add_local v )
    ( add_alias v )
    ( add_sink v ( nurl_str_cat `ij` `kl` ) )
    ^ ( vec_len [s] v )
}
