// let_join_sunk_then_reselected: agora #242 (formal's review) — `: String t ? c a b`, `( consume t )`, then `: String u ? c a b` and `( consume u )`: the second join selected the `a` the first may have moved into `t` and away (let_join_sunk_then_reselected).
// Closed: the second `?`'s arm reads `a` where it ends (bck_handle_cond): maybe-moved, an error.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #242: a `:` join's binding consumed, its owner selected by a second join
$ `stdlib/core/string.nu`

@ consume sink String x → i { ^ ( string_len x ) }

@ main → i {
    : String a ( string_from `a heap string long enough to be on the heap` )
    : String b ( string_from `another heap string long enough for the heap` )
    : i c ( string_len b )
    : String t ? == c 3 a b
    : i n ( consume t )
    : String u ? == c 4 a b
    ^ + n ( consume u )
}
