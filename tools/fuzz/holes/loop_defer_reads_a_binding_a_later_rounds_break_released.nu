// loop_defer_reads_a_binding_a_later_rounds_break_released: `~ c { : String g …  ? d { break } {}  ; { … g … } }`.
// Closed: a `:` binding of a loop body with a `;` further down its block is kept from its binding on (__dloop_open, the statement's __defer_snap_take), so the `break` above the `;` leaves it to the cleanup instead of releasing it (agora #655).
// main ee9d2c5: accepted; round 1's `break`, compiled before the defer kept anything back, releases round 1's `g`, and the defer armed in round 0 reads it (AddressSanitizer: heap-use-after-free).
// map: §5.3 | A2 | runs-clean | - | agora #655: a `break` above a loop body's `;` released the binding the defer, armed in an earlier round, reads
$ `stdlib/core/string.nu`

@ f → i {
    : ~ i k 0
    ~ < k 2 {
        : String g ( string_from `g: a loop string long enough for a heap buffer` )
        ? == k 1 { break } {}
        ; { ( nurl_println_int ( string_len g ) ) }
        = k + k 1
    }
    ^ k
}

@ main → i {
    ( nurl_println_int ( f ) )
    ^ 0
}
