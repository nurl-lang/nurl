// enum_payload_viewed_while_another_variants_arm_grows_its_payload_runs_clean: a view in an `ES` arm, a nested match grows an `EV` payload: never the same storage
// Closed: a change through a `??` payload binding ends the views of the other payload bindings of the same value - by field path, and an enum's only within one variant (bck_borrow_sweep, bck_cursor_follow; agora #874; found by its skeptic pass).
// main 525613db: runs clean (guard).
// map: §2.10 | A2 | runs-clean | - | AGORA-874: a view in an `ES` arm, a nested match grows an `EV` payload: never the same storage
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
    : ~ E e @ E { ES @ H { ( string_from `an enum payload value long enough for the heap` ) } }
    ?? e { ES a → {
            : s v ( string_data . a name )
            ?? e { EV b → { ( vec_push [String] b ( string_from `x` ) ) } ES c → {} EN → {} }
            ( nurl_println v )
        } EN → {} EV q → {} }
    ^ 0
}
