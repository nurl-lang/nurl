// struct_holding_owner_and_its_view_fields_reversed: agora #294 — the same with the owner field first, `@ S2 { b sv }` (struct_holding_owner_and_its_view_fields_reversed).
// Closed: the store row of `b` finds `o` already viewing it, in either field order.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #294: the same with the owner field first, `@ S2 { b sv }`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
: S2 { ( Vec u ) buf ( Slice u ) v }
@ main → i {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push_word_u8 b 9 1 F )
    : ( Slice u ) sv ( slice_from_vec [u] b )
    : S2 o @ S2 { b sv }
    ( vec_reserve [u] . o buf 4096 )
    ( nurl_println_int # i ( slice_at [u] . o v 0 ) )
    ^ 0
}
