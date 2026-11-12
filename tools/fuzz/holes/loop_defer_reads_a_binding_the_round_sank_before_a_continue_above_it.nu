// loop_defer_reads_a_binding_the_round_sank_before_a_continue_above_it: a loop body binding handed to a sink, then a `continue` above the `;` that reads it; the defer an earlier round armed runs at the exit
// Closed: a loop body's binding a `;` further down its body reads is kept across the rounds, and a way out above the `;` replays the defer an earlier round armed against the state there (agora #670); the move this round made of it is a use of a possibly-moved value, as in the straight-line twin (agora #673).
// ee9d2c5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.1 | A2 | rejected | - | agora #673: a loop body binding handed to a sink, then a `continue` above the `;` that reads it; the defer an earlier round armed runs at the exit
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s p i k → String { : ~ String r ( string_from p ) ( string_push_int r k ) ^ r }

@ mg i k → String { ^ ( mk `g: a loop string long enough for a heap buffer ` k ) }

@ pr String g → v { ( nurl_println ( string_data g ) ) }

@ eat sink String x → i { ^ 1 }

@ f i n → i {
    : ~ i k 0
    ~ < k n {
        : String g ( mg k )
        = k + k 1
        ? == k 2 { ( eat g ) continue } {}
        ; { ( pr g ) }
    }
    ^ k
}

@ main → i { ( nurl_println_int ( f 2 ) ) ^ 0 }
