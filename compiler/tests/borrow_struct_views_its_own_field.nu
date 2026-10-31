// borrow_struct_views_its_own_field.nu — agora #294. `o` would take `b` and also a
// slice of `b`: a value that views its own field breaks when that field grows
// or is replaced. It is refused where it is built (A2's SelfFree); the
// message says how to build it instead.

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
