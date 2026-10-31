// struct_holding_owner_and_its_view_field_replaced: agora #294 — the owner field replaced, `= . o buf ( vec_new [u] )`, then `o.v` read (struct_holding_owner_and_its_view_field_replaced).
// Closed: refused where the value is built, before any change to the field.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #294: the owner field replaced, `= . o buf ( vec_new [u] )`, then `o.v` read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
: S { ( Slice u ) v ( Vec u ) buf }
@ main → i {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push_word_u8 b 9 1 F )
    : ( Slice u ) sv ( slice_from_vec [u] b )
    : S o @ S { sv b }
    = . o buf ( vec_new [u] )
    ( nurl_println_int # i ( slice_at [u] . o v 0 ) )
    ^ 0
}
