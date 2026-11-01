// container_join_argument_grown_under_a_slice: agora #314 — 4096 pushes into a `?` choosing a Vec of bytes or another, with a Slice of the first's buffer read after them.
// Closed: a `?` / `??` join as a call's argument hands the callee what one of its arms selects: the bindings its identifier arms name (`__last_phi_idents__`) get the rows a call made with them would (`pendjoin`), so a callee that drops, replaces or moves what it is handed ends their borrows and views, as for the join bound first (agora #314).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #314: a `?` as vec_push's container argument, under a Slice
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec u ) bs ( vec_new [u] )
    ( vec_push [u] bs 7 )
    : ( Vec u ) bt ( vec_new [u] )
    : ( Slice u ) sl ( slice_from_vec [u] bs )
    : i c ( vec_len [u] bs )
    : ~ i k 0
    ~ < k 4096 { ( vec_push [u] ? == c 1 bs bt 1 ) = k + k 1 }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
