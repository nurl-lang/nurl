// struct_given_an_owner_and_a_view_of_it_replaced: the field replaced instead of grown: `= . o buf ( vec_new [u] )`.
// Closed: a value given an owner and a view of that owner at once is refused where it is built — A2's SelfFree (ViewsOK.dropSelf): the store of b into o meets o's dependency on b (bck_diag_self_view; agora #294).
// main 2c20c888: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #294: a value that views its own field
$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`

: S { ( Slice u ) v ( Vec u ) buf }

@ main → i {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push_word_u8 b 9 1 F )
    : ( Slice u ) sv ( slice_from_vec [u] b )
    : ~ S o @ S { sv b }
    = . o buf ( vec_new [u] )
    ( nurl_println_int # i ( slice_at [u] . o v 0 ) )
    ^ 0
}
