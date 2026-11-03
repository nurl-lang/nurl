// option_of_a_vec_of_drop_values_lent_out_of_a_local_returned: agora #459 — `^ ( maybe o k )` of a local `?( Vec D )`, D a `% Drop` value with no copy
// Closed: a function handing back what a call may lend out of a local it drops is refused where the value cannot be copied — an option of a Vec of such values as much as an option of one (agora #459).
// main: accepted; heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #459: `^ ( maybe o k )` of a local `?( Vec D )`
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
