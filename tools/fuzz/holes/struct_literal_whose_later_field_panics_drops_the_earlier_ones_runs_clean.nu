// struct_literal_whose_later_field_panics_drops_the_earlier_ones_runs_clean: under recover, struct literals whose third or fourth field's expression panics after fields the literal made — `% Drop` values, a String, a closure, an option of a `% Drop`.
// Guard for agora #642 item 3: a field the literal made is journaled until the literal is complete (__agg_field_journal), so the panic releases it.
// main 0d1e4d1: accepted, LeakSanitizer: the earlier fields, their destructors never run.
// map: §7.2 | A2 | runs-clean | - | agora #642 item 3 guard: a panic in a struct literal's later field releases the fields already made, once
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_print `` ) } }

: Two { Bomb first Bomb mid Bomb last }
: Mixed { String a ( @ i ) f ? Bomb o Bomb last }

@ bomb i k → Bomb { ^ @ Bomb { ( string_from `a tag long enough for the heap` ) k } }

@ late i on → Bomb { ? == on 1 { ( panic `panic while building` ) } {} ^ ( bomb 9 ) }

@ two → v { : Two t @ Two { ( bomb 0 ) ( bomb 1 ) ( late 1 ) } }

@ mixed → v {
    : String other ( string_from `a captured string, long enough for the heap` )
    : Mixed m @ Mixed { ( string_from `a mixed string, long enough for the heap` ) \ → i { ^ ( string_len other ) } @ ?Bomb { T ( bomb 2 ) } ( late 1 ) }
}

@ main → i {
    : !v PanicInfo a ( recover \ → v { ( two ) } )
    : !v PanicInfo b ( recover \ → v { ( mixed ) } )
    ^ 0
}
