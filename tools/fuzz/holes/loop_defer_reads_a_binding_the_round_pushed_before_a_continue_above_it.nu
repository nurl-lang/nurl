// loop_defer_reads_a_binding_the_round_pushed_before_a_continue_above_it: a loop body binding pushed into an outer Vec, then a `continue` above the `;` that reads it
// Closed: a loop body's binding a `;` further down its body reads is kept across the rounds, and a way out above the `;` replays the defer an earlier round armed against the state there (agora #670); the move this round made of it is a use of a possibly-moved value, as in the straight-line twin (agora #673).
// ee9d2c5: accepted; the defer read a moved-from binding (no fault only because the Vec still held the buffer).
// map: §2.1 | A2 | rejected | - | agora #673: a loop body binding pushed into an outer Vec, then a `continue` above the `;` that reads it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s p i k → String { : ~ String r ( string_from p ) ( string_push_int r k ) ^ r }

@ mg i k → String { ^ ( mk `g: a loop string long enough for a heap buffer ` k ) }

@ pr String g → v { ( nurl_println ( string_data g ) ) }

@ eat sink String x → i { ^ 1 }

@ f ( Vec String ) keep i n → i {
    : ~ i k 0
    ~ < k n {
        : String g ( mg k )
        = k + k 1
        ? == k 2 { ( vec_push [String] keep g ) continue } {}
        ; { ( pr g ) }
    }
    ^ k
}

@ main → i { : ~ ( Vec String ) kp ( vec_new [String] ) ( nurl_println_int ( f kp 2 ) ) ^ 0 }
