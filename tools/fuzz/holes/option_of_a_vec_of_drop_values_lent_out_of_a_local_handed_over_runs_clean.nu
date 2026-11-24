// option_of_a_vec_of_drop_values_lent_out_of_a_local_handed_over_runs_clean: agora #459 — `^ ( maybe o k )` of a local `?( Vec D )`, D a `% Drop` value with no copy
// Closed twice: a function handing back what a call may lend out of a local it drops was refused where the value cannot be copied (agora #459); now that the call answers per call (AGORA-999), the return hands the local itself over on the runs the call lent it (AGORA-995's return handover), and the program runs clean.
// main (v0.80): accepted; heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #459, AGORA-995: `^ ( maybe o k )` of a local `?( Vec D )` hands the local over
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk s t → ?( Vec D ) { : ( Vec D ) v ( vec_new [D] ) ( vec_push [D] v @ D { ( string_from t ) } ) ^ @ ?( Vec D ) { T v } }

@ sh ? ( Vec D ) o → v { ?? o { T v → { ( nurl_println_int ( vec_len [D] v ) ) } F → { ( nurl_println `none` ) } } }

@ maybe ? ( Vec D ) a i k → ?( Vec D ) { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ loc i k → ?( Vec D ) {
    : ?( Vec D ) o ( mk `a local value long enough for the heap` )
    ^ ( maybe o k )
}

@ main → i {
    ( sh ( loc 0 ) )
    ^ 0
}
