// loop_defer_reads_a_view_of_an_earlier_rounds_binding: `~ c { : String g …  ? first { : ( @ i i ) add \ … g …  ; { ( add 1 ) } } {} }`, several rounds.
// Closed: runs clean, and must stay so. The defer, armed in round 0, calls a closure over round 0's `g`; round 1 binds `g` again. A binding a defer reads lives until the defer runs (agora #491), every round's: the value the next round replaces is parked for the cleanup, not released where it is replaced (agora #655) — released there, the defer read freed memory.
// main ee9d2c5: accepted; it ran clean because round 0's `g` was never released at all (LeakSanitizer).
// map: §5.3 | A2 | runs-clean | - | agora #655: a loop defer reads a view of the binding an earlier round made, after a later round bound the name again
$ `stdlib/core/string.nu`

@ f i n → i {
    : ~ i k 0
    ~ < k n {
        : String g ( string_from `g: a loop string long enough for a heap buffer` )
        ? == k 0 {
            : ( @ i i ) add \ i y → i { ^ + y ( string_len g ) }
            : s d ( string_data g )
            ; { ( nurl_println_int ( add 1 ) ) ( nurl_println d ) }
        } {}
        = k + k 1
    }
    ^ k
}

@ main → i {
    ( nurl_println_int ( f 3 ) )
    ^ 0
}
