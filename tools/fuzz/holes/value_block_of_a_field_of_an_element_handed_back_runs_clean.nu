// value_block_of_a_field_of_an_element_handed_back_runs_clean: `@ firstn H h → String { ^ { . ( vec_at [S] . h a 0 ) name } }`, the result read (agora #566, item 4).
// Closed: a value block whose tail is a field read of a call's result is handed back as `^ . ( vec_at … ) name` is, with its per-call answer that it lends: the caller no longer takes it for its own and frees what h's element holds.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | runs-clean | - | agora #566: a value block of a field of a parameter's element handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: S { String name i n }
: R { ( Rc ( Vec S ) ) a ( Rc ( Vec S ) ) z }
: H { ( Vec S ) a ( Vec S ) z }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) { : ( Vec S ) v ( vec_new [S] ) ( vec_push [S] v ( mks t ) ) ^ v }

@ idv ( Vec S ) x → ( Vec S ) { ^ x }

@ firstn H h → String { ^ { . ( vec_at [S] . h a 0 ) name } }

@ main → i {
    : ~ H h @ H { ( mkv `an element string long enough for a heap buffer` ) ( mkv `z` ) }
    : String s ( firstn h )
    ( nurl_println ( string_data s ) )
    ^ 0
}
