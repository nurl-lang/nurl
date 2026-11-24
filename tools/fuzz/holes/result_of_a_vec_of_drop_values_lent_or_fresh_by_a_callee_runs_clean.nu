// result_of_a_vec_of_drop_values_lent_or_fresh_by_a_callee_runs_clean: AGORA-999 — a result `!( Vec D ) i` in place of the option
// Closed: a function that hands back a parameter on one path and a fresh value on another answers per call for an option or result with no copy (__is_hown_ty), so the caller drops the fresh value and not the lent one.
// main: accepted; detected memory leaks (LeakSanitizer: the fresh value).
// map: §7.6 | A2 | runs-clean | - | AGORA-999: a result `!( Vec D ) i` in place of the option
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk s t → ?( Vec D ) { : ( Vec D ) v ( vec_new [D] ) ( vec_push [D] v @ D { ( string_from t ) } ) ^ @ ?( Vec D ) { T v } }

@ sh ? ( Vec D ) o → v { ?? o { T v → { ( nurl_println_int ( vec_len [D] v ) ) } F → { ( nurl_println `none` ) } } }

@ mkr s t → !( Vec D ) i { : ( Vec D ) v ( vec_new [D] ) ( vec_push [D] v @ D { ( string_from t ) } ) ^ @ !( Vec D ) i { T v } }

@ mr ! ( Vec D ) i a i k → !( Vec D ) i { ? == k 0 { ^ a } {} ^ ( mkr `a fresh value long enough for the heap here` ) }

@ main → i {
    : !( Vec D ) i x ( mkr `a local value long enough for the heap` )
    : !( Vec D ) i y ( mr x 1 )
    : !( Vec D ) i z ( mr x 0 )
    ^ 0
}
