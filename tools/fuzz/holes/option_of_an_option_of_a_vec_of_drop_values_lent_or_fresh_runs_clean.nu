// option_of_an_option_of_a_vec_of_drop_values_lent_or_fresh_runs_clean: AGORA-999 — an option of an option of a `Vec D`
// Closed: a function that hands back a parameter on one path and a fresh value on another answers per call for an option or result with no copy (__is_hown_ty), so the caller drops the fresh value and not the lent one.
// main: accepted; detected memory leaks (LeakSanitizer: the fresh value).
// map: §7.6 | A2 | runs-clean | - | AGORA-999: an option of an option of a `Vec D`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk s t → ?( Vec D ) { : ( Vec D ) v ( vec_new [D] ) ( vec_push [D] v @ D { ( string_from t ) } ) ^ @ ?( Vec D ) { T v } }

@ sh ? ( Vec D ) o → v { ?? o { T v → { ( nurl_println_int ( vec_len [D] v ) ) } F → { ( nurl_println `none` ) } } }

@ mm ? ? ( Vec D ) a i k → ?? ( Vec D ) { ? == k 0 { ^ a } {} ^ @ ?? ( Vec D ) { T ( mk `a fresh value long enough for the heap here` ) } }

@ shx ? ? ( Vec D ) o → v { ?? o { T i → { ( sh i ) } F → { ( nurl_println `none` ) } } }

@ main → i {
    : ?? ( Vec D ) x @ ?? ( Vec D ) { T ( mk `a local value long enough for the heap` ) }
    : ?? ( Vec D ) y ( mm x 1 )
    // the lent path, through both option layers: `z` is `x`'s own value,
    // and its scope ends before `x` is read again
    {
        : ?? ( Vec D ) z ( mm x 0 )
        ( shx z )
    }
    ( shx y )
    ( shx x )
    ^ 0
}
