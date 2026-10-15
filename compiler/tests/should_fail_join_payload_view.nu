// should_fail_join_payload_view.nu — a view of the payload out of a `??`
// borrows the container the match read: changing it leaves the view
// dangling.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Fd { i kind ( Vec u ) host }
: Ctx { ( Vec Fd ) fds }

@ main → i {
    : ~ Ctx c @ Ctx { ( vec_new [Fd] ) }
    ( vec_push [Fd] . c fds @ Fd { 2 ( vec_new [u] ) } )
    : ( Slice u ) hb ?? ( vec_get [Fd] . c fds 0 ) { T d → ( slice_from_vec [u] . d host ) F → ( slice_empty [u] ) }
    ( vec_clear [Fd] . c fds )
    ^ ( slice_len [u] hb )
}
