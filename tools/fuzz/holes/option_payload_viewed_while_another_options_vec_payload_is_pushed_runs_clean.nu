// option_payload_viewed_while_another_options_vec_payload_is_pushed_runs_clean: a view of one option's payload, `vec_push` into another option's payload
// Closed: a change through a `??` payload binding ends the views of the other payload bindings of the same value - by field path, and an enum's only within one variant (bck_borrow_sweep, bck_cursor_follow; agora #874; found by its skeptic pass).
// main 525613db: runs clean (guard).
// map: §2.10 | A2 | runs-clean | - | AGORA-874: a view of one option's payload, `vec_push` into another option's payload
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { String name }
: H2 { String x String y }
: | E { EN ES H EV ( Vec String ) }
: W { ? String f1 ? String f2 }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ grow String s → v { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) }

@ main → i {
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : ~ ? ( Vec i ) p @ ?( Vec i ) { T ( vec_new [i] ) }
    ?? o { T a → {
            : s v ( string_data a )
            ?? p { T b → { ( vec_push [i] b 3 ) } F → {} }
            ( nurl_println v )
        } F → {} }
    ^ 0
}
