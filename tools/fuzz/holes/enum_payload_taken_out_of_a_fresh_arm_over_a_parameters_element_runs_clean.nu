// enum_payload_taken_out_of_a_fresh_arm_over_a_parameters_element_runs_clean:
// `: ( Vec M ) v ( vec_at pvm 0 )  : M m ? == f 1 @ M { Text ( string_from … ) } (
// vec_at [M] v 0 )  ?? m { Text t → { ^ t } … }`: on the fresh run m owns the
// literal and t is taken out of it. #560's first version answered every run
// "lent" (v always lends), so the taken String leaked; the take bit now
// stands where the payload was taken (agora #560, adversarial w9).
// map: §7.6 | A2 | runs-clean | - | an enum payload taken out of a fresh join arm beside a parameter's element: must stay owned where taken (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`
$ `stdlib/std/panic.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ showlive i l0 → v { ( nurl_println ( nurl_str_cat `LIVE ` ( nurl_str_int - ( live ) l0 ) ) ) }

: P { String s i n }
: PV { ( Vec String ) items i n }
: PO { ? String o i n }
: W { P p i k }
: | M { Text String Num i }

@ first ( Vec ( Vec M ) ) pvm i f → String {
    : ( Vec M ) v ( vec_at [( Vec M )] pvm 0 )
    : M m ? == f 1 @ M { Text ( string_from `fresh` ) } ( vec_at [M] v 0 )
    ?? m { Text t → { ^ t } Num k → { ^ ( string_new ) } }
}

@ use ( Vec ( Vec M ) ) vv → v { : String a ( first vv 1 ) ( nurl_println ( string_data a ) ) }

@ main → i {
    : ( Vec ( Vec M ) ) vv ( vec_new [( Vec M )] )
    : ( Vec M ) in0 ( vec_new [M] )
    ( vec_push [M] in0 @ M { Text ( string_from `elem` ) } )
    ( vec_push [( Vec M )] vv in0 )
    : i l0 ( live ) ( use vv ) ( showlive l0 )
    ^ 0
}
