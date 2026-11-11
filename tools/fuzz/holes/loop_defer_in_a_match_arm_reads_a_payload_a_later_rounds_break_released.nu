// loop_defer_in_a_match_arm_reads_a_payload_a_later_rounds_break_released: `~ c { ?? ( make k ) { T t → { ? d { break } {}  ; { … t … } } F → { } } }`.
// Closed: an arm's block that holds a `;`, in a defer loop, keeps what is in sight at its head — the payloads the arm bound — from there, so the `break` above the `;` leaves the round's payload to the cleanup; and the payload an earlier round left there is parked when the arm binds it again, not written over (mem_dkeep_rebind at the payload's slot; agora #698).
// main 1b2a935: accepted; round 2's `break` releases round 2's payload and the defer armed in round 0 reads it (AddressSanitizer: heap-use-after-free); with no `break`, every round's payload but the last is never released.
// map: §5.3 | A2 | runs-clean | - | agora #698: a `break` in a match arm above its `;` released the payload the defer, armed in an earlier round, reads
$ `stdlib/core/string.nu`

@ make i k → ?String {
    : ~ String r ( string_from `g: a loop string long enough for a heap buffer ` )
    ( string_push_int r k )
    ^ @ ?String { T r }
}

@ f i n → i {
    : ~ i k 0
    ~ < k 4 {
        ?? ( make k ) {
            T t → {
                ? == k n { break } {}
                ; { ( nurl_println ( string_data t ) ) }
            }
            F → {}
        }
        = k + k 1
    }
    ^ k
}

@ main → i {
    ( nurl_println_int ( f 2 ) )
    ( nurl_println_int ( f 9 ) )
    ^ 0
}
