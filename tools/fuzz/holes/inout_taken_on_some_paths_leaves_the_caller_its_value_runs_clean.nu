// inout_taken_on_some_paths_leaves_the_caller_its_value_runs_clean: a function hands its `inout ( Vec S )` parameter to a `sink` on some paths only — a join arm, a block arm, one arm of a statement `?`, through another `inout`; both paths run.
// Closed (agora #776): an `inout` parameter of a handle type is never consumed; its caller's slot is emptied where it is handed on (#778, and now a join that selects it), and the caller drops its binding as ever.
// main 160339c1: the caller's value leaks on every path that takes nothing (definitely lost).
// map: §7.6 | A2 | runs-clean | - | agora #776: an inout handed to a sink on some paths only
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ mkv i k → ( Vec S ) { : ( Vec S ) v ( vec_new [S] ) ( vec_push [S] v @ S { ( string_from `a name long enough to own a heap buffer` ) k } ) ^ v }

@ g inout ( Vec S ) p i c → i { ^ ( eat ? == c 1 p ( mkv 3 ) ) }

@ g2 inout ( Vec S ) p i c → i { ^ ( eat ? == c 1 { p } ( mkv 3 ) ) }

@ g3 inout ( Vec S ) p i c → i { ? == c 1 { ^ ( eat p ) } {} ^ 0 }

@ g4 inout ( Vec S ) p i c → i { ^ ( g3 p c ) }

@ run i c → v {
    : ~ ( Vec S ) w ( mkv 1 ) ( nurl_println_int ( g w c ) )
    : ~ ( Vec S ) w2 ( mkv 1 ) ( nurl_println_int ( g2 w2 c ) )
    : ~ ( Vec S ) w3 ( mkv 1 ) ( nurl_println_int ( g3 w3 c ) )
    : ~ ( Vec S ) w4 ( mkv 1 ) ( nurl_println_int ( g4 w4 c ) )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
