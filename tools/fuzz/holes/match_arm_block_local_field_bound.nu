// match_arm_block_local_field_bound: agora #180 — a `??` arm block's tail field of the arm's own struct, bound by a `:` (match_arm_block_local_field_bound).
// Closed: an arm whose value is a field of a struct the arm owns itself moves it out of that struct (a struct with a `% Drop` of its own keeps a copy), so the arm's locals are dropped at its exit (mem_arm_take_field; agora #180).
// v0.80.0 and main: accepted; LeakSanitizer (the struct was never dropped).
// map: §7.6 | A2 | runs-clean | h751 | agora #180: a `??` arm block's tail field of the arm's own struct, bound by a `:`
$ `stdlib/core/string.nu`

: P { String s i n }

: | G {
    V P
    Nil
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : G g @ G { V @ P { ( mk ) 1 } }
    : String t ?? g { V p → { : P q @ P { ( mk ) 2 } . q s } Nil → ( mk ) }
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
