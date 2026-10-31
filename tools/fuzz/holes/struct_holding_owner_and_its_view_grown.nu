// struct_holding_owner_and_its_view_grown: agora #294 — `: S o @ S { sv b }` with `sv` a slice of `b`, then `o.buf` grown and `o.v` read (struct_holding_owner_and_its_view_grown).
// Closed: a value that takes an owner it holds a view of is refused where it is built (bck_views_part at the store row; A2 SelfFree).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #294: `: S o @ S { sv b }` with `sv` a slice of `b`, then `o.buf` grown and `o.v` read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
: S { ( Slice u ) v ( Vec u ) buf }
@ main → i {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push_word_u8 b 9 1 F )
    : ( Slice u ) sv ( slice_from_vec [u] b )
    : S o @ S { sv b }
    ( vec_reserve [u] . o buf 4096 )
    ( nurl_println_int # i ( slice_at [u] . o v 0 ) )
    ^ 0
}
