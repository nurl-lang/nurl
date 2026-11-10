// struct_given_a_view_and_its_owner_in_the_other_order: the field order reversed: `@ S2 { b sv }`.
// Closed: a value given an owner and a view of that owner at once is refused where it is built — A2's SelfFree (ViewsOK.dropSelf): the store of b into o meets o's dependency on b (bck_diag_self_view; agora #294).
// main 2c20c888: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #294: a value that views its own field
$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`

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
