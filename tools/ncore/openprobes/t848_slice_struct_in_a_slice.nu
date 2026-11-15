// map: §7.6 | A2 | runs-clean | - | agora #848: `: H { [String names i n }` as an element of a `[H` slice: its slice and Strings are never freed
$ `stdlib/core/string.nu`

: H { [String names i n }

@ main → i {
    : [H hs [H | @ H { [String | ( string_from `a name long enough for a heap buffer` )] 1 }]
    ~ h hs { ( nurl_println_int . h n ) }
    ^ 0
}
