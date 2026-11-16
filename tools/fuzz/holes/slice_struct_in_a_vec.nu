// slice_struct_in_a_vec:
// AGORA-869: closed (main 3358873a: faulted under ASan); agora #848.
// map: §7.6 | A2 | runs-clean | - | agora #848: `: H { [String names i n }` stored in a Vec: its slice and Strings are never freed
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { [String names i n }

@ main → i {
    : ( Vec H ) v ( vec_new [H] )
    ( vec_push [H] v @ H { [String | ( string_from `a name long enough for a heap buffer` )] 1 } )
    ( nurl_println_int ( vec_len [H] v ) )
    ^ 0
}
