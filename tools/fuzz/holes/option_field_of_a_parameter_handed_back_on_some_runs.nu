// option_field_of_a_parameter_handed_back_on_some_runs: agora #459 — `^ . h o` (a `?String` field of a parameter) on one path, a fresh value on another
// Closed: a function handing back an option field of a parameter (`^ . h o`) answers "lent" per call, as for a String or Vec field (gen_ret __rb_read; agora #459).
// main: heap-use-after-free (base d430345e too).
// map: §7.6 | A2 | runs-clean | - | agora #459: `^ . h o` (a `?String` field of a parameter) on one path, a fresh value on another
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

: H { ? String o i n }

@ pick H h i k → ?String {
    ? == k 0 { ^ . h o } {}
    ^ ( mk `a fresh value long enough for the heap here` )
}

@ main → i {
    : ~ H h @ H { ( mk `the field value, long enough for the heap` ) 1 }
    : ?String x ( pick h 0 )
    ( show x )
    ( show . h o )
    ^ 0
}
