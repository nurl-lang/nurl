// diag_nc_local_lend_through_an_inline_slice.nu — `^ ( slice_at [D] (
// slice_from_vec [D] ds ) 0 )`, ds a local of a type with a user drop: what
// slice_at lends comes out of ds through the inline slice, ds is dropped on
// the way out, and a D cannot be copied, so this is refused. The message
// names ds, the local the lend comes out of, not the inline call (agora
// #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ mkps → ( Vec P ) { : ( Vec P ) ps ( vec_new [P] ) ( vec_push [P] ps @ P { ( string_from `payload field string long enough` ) } ) ^ ps }

@ mkrs → ( Vec R ) { : ( Vec R ) rs ( vec_new [R] ) ( vec_push [R] rs @ R { @ ?String { T ( string_from `option field string long enough` ) } } ) ^ rs }

@ mkqs → ( Vec Q ) { : ( Vec Q ) qs ( vec_new [Q] ) ( vec_push [Q] qs @ Q { @ P { ( string_from `nested field string long enough` ) } } ) ^ qs }

@ first → D { : ( Vec D ) ds ( vec_new [D] ) ( vec_push [D] ds @ D { ( string_from `a d long enough for the heap buffer` ) } ) ^ ( slice_at [D] ( slice_from_vec [D] ds ) 0 ) }

@ main → i { : D r ( first ) ( nurl_println ( string_data . r s ) ) ^ 0 }
