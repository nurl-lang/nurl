// loop_defer_keeps_each_rounds_binding_the_next_round_writes_over: `~ c { : String g …  : ( Vec String ) v …  : ( @ i i ) add \ … g …  ; { … } }`, several rounds.
// Closed: a kept binding of a loop body parks what its slot holds from an earlier round before this round's value is stored (mem_dkeep_rebind, __dkr_expand), and the cleanup releases the parked values after the defer chain, newest first (__dkdrain): a String, a Vec and a closure's environment (agora #655).
// main ee9d2c5: accepted; each round's end skips what the defer keeps and the next round's `:` writes over the slot: every round's String, Vec and environment but the last is never released (LeakSanitizer).
// map: §7.1 | A2 | runs-clean | - | agora #655: each round's binding a loop body's `;` keeps, but the last, leaked
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f i n → i {
    : ~ i k 0
    ~ < k n {
        : String g ( string_from `g: a loop string long enough for a heap buffer` )
        : ~ ( Vec String ) v ( vec_new [String] )
        ( vec_push [String] v ( string_from `an element long enough for a heap buffer` ) )
        : ( @ i i ) add \ i x → i { ^ + x ( string_len g ) }
        ; { ( nurl_println_int + ( add 1 ) ( vec_len [String] v ) ) }
        = k + k 1
    }
    ^ k
}

@ main → i {
    ( nurl_println_int ( f 4 ) )
    ^ 0
}
