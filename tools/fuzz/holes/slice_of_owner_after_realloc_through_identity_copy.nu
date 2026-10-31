// slice_of_owner_after_realloc_through_identity_copy: agora #293 — `: ( Slice i ) sl ( slice_from_vec [i] vs )`, then `: ( Vec i ) w ( id vs )` and `( vec_reserve [i] w 4096 )`, then a read of `sl`: the realloc went through a copy of `vs`'s own handle, and only views into elements' buffers ended (slice_of_owner_after_realloc_through_identity_copy).
// Closed: a borrow whose bytes are a binding's own value (bck_byte_root's odd code) is that binding's handle, so a realloc through it ends that binding's views, as when the call names it.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #293: a slice of an owner read after its buffer moved through an identity copy of its handle
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ id ( Vec i ) x → ( Vec i ) { ^ x }

@ main → i {
    : ( Vec i ) vs ( vec_new [i] )
    ( vec_push [i] vs 7 )
    : ( Slice i ) sl ( slice_from_vec [i] vs )
    : ( Vec i ) w ( id vs )
    ( vec_reserve [i] w 4096 )
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
