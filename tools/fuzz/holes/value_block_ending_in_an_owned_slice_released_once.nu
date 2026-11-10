// value_block_ending_in_an_owned_slice_released_once: agora #545 — a value block whose value is an owned slice (`{ : i n 3 [i | n n] }`, `{ : [i t [i | 3 4] t }`, a struct holding one) and a slice returned past a `;` defer: the block's value was released by the block and by what it was bound to, or by neither.
// Closed: a value block hands its value to what the block is the value of, once: the block's own binding moves out, a literal or a call's result has no second owner, and a return past a defer hands over the binding the defer still reads before it runs.
// main (before this PR): LeakSanitizer, the slices left behind.
// map: §7.6 | A2 | runs-clean | - | agora #545: an owned slice as a value block's value, or returned past a defer, was released twice or never
: H { [i items i n }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }
@ mk → [i { ^ [i | 7 8] }

@ past_defer i n → [i {
    : [i a [i | 1 2 3]
    ; { ( nurl_println ( nurl_str_int ( sum a ) ) ) }
    ? == n 0 { ^ a } {}
    ^ [i | 100]
}

@ main → i {
    : [i a { : i n 3 [i | n n] }
    : [i a2 { : i n 4 ( mk ) }
    ( nurl_println ( nurl_str_int + ( sum a ) ( sum a2 ) ) )
    : ~ [i c [i | 0]
    = c { [i | 1 2] }
    = c { : [i t [i | 3 4] t }
    ( nurl_println ( nurl_str_int ( sum c ) ) )
    : H h { @ H { [i | 1 2] 2 } }
    ( nurl_println ( nurl_str_int ( sum . h items ) ) )
    : [i r0 ( past_defer 0 )
    : [i r1 ( past_defer 1 )
    ( nurl_println ( nurl_str_int + ( sum r0 ) ( sum r1 ) ) )
    ^ 0
}
