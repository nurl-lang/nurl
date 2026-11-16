// map: §7.6 | A2 | rejected | - | AGORA-876: : R r p ^ r with p kept on another path
// main 3358873a: faults under ASan (found by AGORA-869's adversarial pass).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mkr s t → R { ^ @ R { ( string_from t ) 1 } }

@ g0 R p → R { ^ p }

@ eat sink R r → v { ( nurl_println ( string_data . r s ) ) }

@ f ( Vec R ) log R p b keep → R { ? keep { ( vec_push [R] log p ) ^ ( mkr `kept` ) } {} : R r p ^ r }

@ run b keep → v {
    : ~ ( Vec R ) log ( vec_new [R] )
    : R x ( mkr `first value long enough for the heap, surely so` )
    : R a ( f log x keep )
    ( nurl_println ( string_data . a s ) )
    ( nurl_println_int ( vec_len [R] log ) )
}

@ main → i { ( run T ) ( run F ) ^ 0 }
