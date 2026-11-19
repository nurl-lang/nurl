// slice_join_then_only_arm_of_a_fresh_slice_runs_clean: `? c { ( mk ) } {}`, `? c { ( mks ) } {}` (a slice of Strings), `? c { ( g ) } {}` with g a closure making one, and `? c { ( id a ) } {}` lending a binding: a then-only arm's discarded slice
// Closed (agora #903): a then-only arm's discarded tail slice is released where the arm ends, by the call's own answer (__slice_call_own_bit, mem_arm_tail_own), as the same call discarded as a statement is; a lent one stays its owner's.
// main 85a31ca: LeakSanitizer: the fresh slices (and the Strings in one) leaked.
// map: §7.6 | A2 | runs-clean | - | agora #903: a then-only arm's discarded fresh slice, of numbers, of Strings and from a closure, and one lending a binding
$ `stdlib/core/string.nu`

@ mk → [i { ^ [i | 1 2 3] }
@ mks → [String { ^ [String | ( string_from `a string long enough for a heap buffer` )] }
@ id [i x → [i { ^ x }

@ main → i {
    : [i a [i | 4 5]
    : ( @ [i ) g \ → [i { ^ [i | 7] }
    : i c 1
    ? > c 0 { ( mk ) } {}
    ? > c 0 { ( mks ) } {}
    ? > c 0 { ( g ) } {}
    ? > c 0 { ( id a ) } {}
    ~ x a { ( nurl_println_int x ) }
    ^ 0
}
