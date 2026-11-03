// result_field_of_a_parameter_handed_back_on_some_runs: agora #459 — as option_field_of_a_parameter_handed_back_on_some_runs, a result field
// Closed: a function handing back an option field of a parameter (`^ . h o`) answers "lent" per call, as for a String or Vec field (gen_ret __rb_read; agora #459).
// main: heap-use-after-free (base d430345e too).
// map: §7.6 | A2 | runs-clean | - | agora #459: as option_field_of_a_parameter_handed_back_on_some_runs, a result field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

: | E { Bad }
: H { ! String E r i n }

@ pick H h i k → !String E { ? == k 0 { ^ . h r } {} ^ @ !String E { T ( string_from `a fresh value long enough for the heap here` ) } }

@ sh ! String E o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F _ → { ( nurl_println `bad` ) } } }

@ main → i {
    : H h @ H { @ !String E { T ( string_from `the result field long enough for the heap` ) } 1 }
    : !String E x ( pick h 0 )
    ( sh x )
    ( sh . h r )
    ^ 0
}
