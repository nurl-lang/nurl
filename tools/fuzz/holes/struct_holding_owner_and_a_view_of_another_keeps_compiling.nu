// struct_holding_owner_and_a_view_of_another_keeps_compiling: agora #294 — a value holding an owner of its own beside a view of ANOTHER binding (precision pin) (struct_holding_owner_and_a_view_of_another_keeps_compiling).
// Pin: only a view of what the value itself takes is refused.
// main: accepted, ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #294: a value holding an owner of its own beside a view of ANOTHER binding (precision pin)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
: S { ( Slice u ) v ( Vec u ) buf }
@ main → i {
    : ( Vec u ) c ( vec_new [u] )
    ( vec_push_word_u8 c 7 1 F )
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push_word_u8 b 9 1 F )
    : ( Slice u ) sv ( slice_from_vec [u] c )
    : S o @ S { sv b }
    ( vec_reserve [u] . o buf 4096 )
    ( nurl_println_int # i ( slice_at [u] . o v 0 ) )
    ^ 0
}
