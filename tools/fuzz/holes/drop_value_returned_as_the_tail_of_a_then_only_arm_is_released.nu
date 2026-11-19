// drop_value_returned_as_the_tail_of_a_then_only_arm_is_released: `? c { ( mk ) } {}` with `mk` handing back a value of a `% Drop` type: the arm's discarded tail value is released where the arm ends, and its destructor runs
// Closed: mem_arm_tail_own owns a non-copyable `% Drop` tail value as it owns a handle (agora #917).
// main 5f3d33e: accepted; LeakSanitizer: direct leak of 24 bytes, the destructor never ran.
// map: §2.14 | A2 | runs-clean | - | agora #917: a % Drop value a call returns as the tail of a then-only arm, released where the arm ends
$ `stdlib/core/string.nu`

: H { String a }

% Drop H { @ drop H h → v { ( nurl_println_int # i ( string_len . h a ) ) } }

@ mk → H { ^ @ H { ( string_from `abc` ) } }

@ main → i {
    : i c 1
    ? > c 0 { ( mk ) } {}
    ? > c 0 { ( nurl_println_int 1 ) ( mk ) } {}
    ^ 0
}
