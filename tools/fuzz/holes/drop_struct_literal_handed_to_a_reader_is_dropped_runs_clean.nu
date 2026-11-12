// drop_struct_literal_handed_to_a_reader_is_dropped_runs_clean: a struct literal with two `% Drop` fields and a String, and one with a `% Drop` field and a closure, each handed straight to a function that only reads it.
// Guard for agora #642 item 2: the fields such a literal makes are its own, dropped after the call (the literal-argument rule, `__ao_ty`), a `% Drop` value's as a handle's are.
// main 0d1e4d1: accepted, LeakSanitizer: the `% Drop` fields' Strings, their destructors never run.
// map: §7.2 | A2 | runs-clean | - | agora #642 item 2 guard: a struct literal handed to a borrowing parameter drops its `% Drop` fields after the call
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_print `` ) } }

: S5 { Bomb x String m Bomb y }
: C { Bomb x ( @ i ) f }

@ bomb i k → Bomb { ^ @ Bomb { ( string_from `a tag long enough for the heap` ) k } }

@ look S5 s → i { ^ ( string_len . s m ) }

@ lookc C c → i { : ( @ i ) g . c f ^ ( g ) }

@ main → i {
    : i n ( look @ S5 { ( bomb 0 ) ( string_from `m, long enough for the heap` ) ( bomb 1 ) } )
    : String other ( string_from `a captured string, long enough for the heap` )
    : i k ( lookc @ C { ( bomb 2 ) \ → i { ^ ( string_len other ) } } )
    ( nurl_println ( nurl_str_int + n k ) )
    ^ 0
}
