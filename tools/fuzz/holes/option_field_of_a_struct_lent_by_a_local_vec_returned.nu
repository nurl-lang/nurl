// option_field_of_a_struct_lent_by_a_local_vec_returned: agora #300 — (f5) an option field of a struct read with vec_at out of a local Vec, its payload returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (f5) an option field of a struct read with vec_at out of a local Vec, its payload returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: H { ? String o }

@ pick i k → String {
    : ( Vec H ) hs ( vec_new [H] )
    ( vec_push [H] hs @ H { @ ?String { T ( string_from `an element string long enough for the heap` ) } } )
    : H h ( vec_at [H] hs 0 )
    ?? . h o { T e → { ^ e } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
