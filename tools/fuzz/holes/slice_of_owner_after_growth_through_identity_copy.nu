// slice_of_owner_after_growth_through_identity_copy: agora #293 — the push-loop form: `~ < k 1000 { ( vec_push [i] w k ) … }` through `: ( Vec i ) w ( id vs )` grows `vs`'s own buffer under a slice of it (slice_of_owner_after_growth_through_identity_copy).
// Closed: the realloc through a borrow whose code is odd ends that binding's views (bck_byte_root, agora #293).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #293: a slice of an owner read after pushes through an identity copy grew its buffer
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
@ id ( Vec i ) x → ( Vec i ) { ^ x }
@ main → i {
    : ( Vec i ) vs ( vec_new [i] )
    ( vec_push [i] vs 7 )
    : ( Slice i ) sl ( slice_from_vec [i] vs )
    : ( Vec i ) w ( id vs )
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] w k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
