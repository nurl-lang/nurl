// option_of_a_vec_of_drop_values_lent_by_a_generic_out_of_a_temporary: AGORA-999 — a generic `maybeg [ ?( Vec D ) ]` handing back a temporary argument
// Guard: refused, as the same call is for a `( Vec D )`: the temporary would have to outlive the statement and the value has no copy. main accepted it and leaked.
// main: accepted; detected memory leaks.
// map: §7.6 | A2 | rejected | - | AGORA-999: a generic lending a temporary argument with no copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk s t → ?( Vec D ) { : ( Vec D ) v ( vec_new [D] ) ( vec_push [D] v @ D { ( string_from t ) } ) ^ @ ?( Vec D ) { T v } }

@ sh ? ( Vec D ) o → v { ?? o { T v → { ( nurl_println_int ( vec_len [D] v ) ) } F → { ( nurl_println `none` ) } } }

@ maybeg [T] T a i k T b → T { ? == k 0 { ^ a } {} ^ b }

@ main → i {
    : ?( Vec D ) x ( mk `a local value long enough for the heap` )
    ( sh ( maybeg [? ( Vec D )] x 1 ( mk `a fresh value long enough for the heap here` ) ) )
    ( sh ( maybeg [? ( Vec D )] x 0 ( mk `another fresh value long enough for the heap` ) ) )
    ( sh x )
    ^ 0
}
