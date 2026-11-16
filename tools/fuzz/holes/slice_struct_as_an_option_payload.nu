// slice_struct_as_an_option_payload:
// AGORA-869: closed (main 3358873a: faulted under ASan); agora #848.
// map: §7.6 | A2 | runs-clean | - | agora #848: `: H { [String names i n }` as an option payload `?H`: its slice and Strings are never freed
$ `stdlib/core/string.nu`

: H { [String names i n }

@ main → i {
    : ?H o @ ?H { T @ H { [String | ( string_from `a name long enough for a heap buffer` )] 1 } }
    ?? o { T h → ( nurl_println_int . h n ) F → ( nurl_println_int 0 ) }
    ^ 0
}
