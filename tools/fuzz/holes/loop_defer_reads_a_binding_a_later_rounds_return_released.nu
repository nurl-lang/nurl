// loop_defer_reads_a_binding_a_later_rounds_return_released: `~ c { : String g …  ? d { ^ 7 } {}  ; { … g … } }`.
// Closed: the binding is kept from its binding on, so the `^` above the `;` leaves round 1's `g` to the cleanup, which releases it once, and round 0's after it, parked when round 1 bound the name again (agora #655).
// main ee9d2c5: accepted; the `^` releases round 1's `g`, fn_cleanup releases it again (AddressSanitizer: attempting double-free), and round 0's `g` is never released.
// map: §5.3 | A2 | runs-clean | - | agora #655: a `^` above a loop body's `;` released the binding the defer keeps, and the cleanup released it again
$ `stdlib/core/string.nu`

@ f → i {
    : ~ i k 0
    ~ < k 2 {
        : String g ( string_from `g: a loop string long enough for a heap buffer` )
        ? == k 1 { ^ 7 } {}
        ; { ( nurl_println_int ( string_len g ) ) }
        = k + k 1
    }
    ^ k
}

@ main → i {
    ( nurl_println_int ( f ) )
    ^ 0
}
