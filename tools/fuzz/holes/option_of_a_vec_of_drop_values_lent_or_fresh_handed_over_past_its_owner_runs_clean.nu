// option_of_a_vec_of_drop_values_lent_or_fresh_handed_over_past_its_owner_runs_clean: AGORA-999 — `^ ( maybe x 0 )` of a local `x` the function drops
// Answered per call (AGORA-999), the call hands `x` back whole on the runs it lends, so the return hands `x` itself over there: its flag is cleared and the caller owns the value, nothing is copied and nothing outlives its owner (AGORA-995's return handover, as for a `( Vec D )`). Before the handover this was refused, as the `( Vec D )` twin was (#187).
// main: rejected.
// map: §7.6 | A2 | runs-clean | - | AGORA-999/995: the lent answer of a local handed back is the local handed over
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk s t → ?( Vec D ) { : ( Vec D ) v ( vec_new [D] ) ( vec_push [D] v @ D { ( string_from t ) } ) ^ @ ?( Vec D ) { T v } }

@ sh ? ( Vec D ) o → v { ?? o { T v → { ( nurl_println_int ( vec_len [D] v ) ) } F → { ( nurl_println `none` ) } } }

@ maybe ? ( Vec D ) a i k → ?( Vec D ) { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ esc → ?( Vec D ) {
    : ?( Vec D ) x ( mk `a local value long enough for the heap` )
    ^ ( maybe x 0 )
}

@ main → i { ( sh ( esc ) ) ^ 0 }
