// option_of_a_vec_of_drop_values_lent_or_fresh_kept_beside_its_owner_runs_clean: AGORA-999 — both answers bound beside the owner they may lend
// Closed: a function that hands back a parameter on one path and a fresh value on another answers per call for an option or result with no copy (__is_hown_ty), so the caller drops the fresh value and not the lent one.
// main: accepted; detected memory leaks (LeakSanitizer: the fresh value).
// map: §7.6 | A2 | runs-clean | - | AGORA-999: both answers bound beside the owner they may lend
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk s t → ?( Vec D ) { : ( Vec D ) v ( vec_new [D] ) ( vec_push [D] v @ D { ( string_from t ) } ) ^ @ ?( Vec D ) { T v } }

@ sh ? ( Vec D ) o → v { ?? o { T v → { ( nurl_println_int ( vec_len [D] v ) ) } F → { ( nurl_println `none` ) } } }

@ maybe ? ( Vec D ) a i k → ?( Vec D ) { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ main → i {
    : ?( Vec D ) x ( mk `a local value long enough for the heap` )
    : ?( Vec D ) y ( maybe x 0 )
    : ?( Vec D ) z ( maybe x 1 )
    ( sh y ) ( sh z ) ( sh x )
    ^ 0
}
