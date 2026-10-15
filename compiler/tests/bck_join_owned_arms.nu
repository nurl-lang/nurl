// bck_join_owned_arms.nu — a `??` whose arms each hand over a value of
// their own (a clone of the payload, a fresh Vec) borrows nothing from what
// it matched on: the container may change after it. (A payload VIEW out of
// the same match still borrows it — should_fail_join_payload_view.)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Fd { i kind ( Vec u ) host }
: Ctx { ( Vec Fd ) fds }

@ main → i {
    : ~ Ctx c @ Ctx { ( vec_new [Fd] ) }
    : ~ ( Vec u ) h0 ( vec_new [u] )
    ( vec_push [u] h0 # u 47 ) ( vec_push [u] h0 # u 116 )
    ( vec_push [Fd] . c fds @ Fd { 2 h0 } )
    : ( Vec u ) hb ?? ( vec_get [Fd] . c fds 0 ) { T d → ( vec_clone [u] . d host ) F → ( vec_new [u] ) }
    ( vec_clear [Fd] . c fds )
    ( nurl_println ( nurl_str_int ( vec_len [u] hb ) ) )
    ( nurl_println ( nurl_str_int # i ( vec_at [u] hb 1 ) ) )
    ^ 0
}
