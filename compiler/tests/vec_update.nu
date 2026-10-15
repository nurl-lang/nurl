// vec_update / vec_apply: a closure changes one element in place — a record
// that owns buffers is neither copied nor moved — and an index out of range
// runs nothing.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Fd { i pos ( Vec u ) data }
: Ctx { ( Vec Fd ) fds i calls }

@ write_at inout Ctx c i k i byte → b {
    ^ ( vec_update [Fd] . c fds k \ inout Fd f → v { ( vec_push [u] . f data # u byte ) = . f pos + . f pos 1 } )
}

@ main → i {
    : ~ Ctx c @ Ctx { ( vec_new [Fd] ) 0 }
    ( vec_push [Fd] . c fds @ Fd { 0 ( vec_new [u] ) } )
    ( vec_push [Fd] . c fds @ Fd { 0 ( vec_new [u] ) } )
    : b a ( write_at c 1 65 )
    : b b2 ( write_at c 1 66 )
    : b miss ( write_at c 7 67 )
    // a result out of the element; the fallback when the index is out of range
    : i n1 ( vec_apply [Fd i] . c fds 1 -1 \ inout Fd f → i { ^ + * 10 . f pos ( vec_len [u] . f data ) } )
    : i n9 ( vec_apply [Fd i] . c fds 9 -1 \ inout Fd f → i { ^ . f pos } )
    ( nurl_println ( nurl_str_int ? a 1 0 ) )
    ( nurl_println ( nurl_str_int ? b2 1 0 ) )
    ( nurl_println ( nurl_str_int ? miss 1 0 ) )
    ( nurl_println ( nurl_str_int n1 ) )
    ( nurl_println ( nurl_str_int n9 ) )
    ( nurl_println ( nurl_str_int . ( vec_at [Fd] . c fds 0 ) pos ) )
    ^ 0
}
