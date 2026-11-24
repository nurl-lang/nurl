// option_of_a_vec_of_drop_values_lent_or_fresh_handed_past_its_owner: AGORA-999 — `^ ( maybe x 0 )` of a local `x` the function drops
// Guard: answered per call, the lent answer still cannot outlive `x`; refused, as a `( Vec D )` is.
// main: rejected.
// map: §7.6 | A2 | rejected | - | AGORA-999: the lent answer handed past its owner
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
