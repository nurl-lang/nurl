// loop_defer_keeps_each_rounds_slice_the_next_round_writes_over: `~ c { : [i xs [i | …]  : [String ss [String | …]  ; { … xs … ss … } }`, several rounds.
// Closed: a kept loop binding that is an owned slice is parked when the next round binds the name again — its `{ data, length }` goes onto the loop's list under its "left to the cleanup" flag — and the cleanup releases its elements and its buffer after the defer chain (__dkr_expand_slice, `__dkdrop_sl_<type>`; agora #676).
// main 1b2a935: accepted; every round's buffer but the last, and the Strings a slice of Strings holds, are never released (LeakSanitizer), though a Vec beside them is.
// map: §7.1 | A2 | runs-clean | - | agora #676: each round's owned slice a loop body's `;` keeps, but the last, leaked
$ `stdlib/core/string.nu`

@ f i n → i {
    : i z 0
    : ~ i k 0
    ~ < k n {
        : [i xs [i | k 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16]
        : [String ss [String | ( string_from `an element long enough for a heap buffer, yes` )]
        ; { ( nurl_println_int + . xs z ( string_len . ss z ) ) }
        = k + k 1
    }
    ^ k
}

@ main → i {
    ( nurl_println_int ( f 3 ) )
    ^ 0
}
