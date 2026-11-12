// binding_moved_into_a_literal_whose_later_field_panics_is_dropped_runs_clean: under recover, `% Drop` bindings moved into struct literals (a flat one, a nested one, one handed to a reader, an option's payload) whose later field's expression panics.
// Guard for agora #741: a binding moved in hands its value over at the literal's `}` (gen_agg_lit defers its drop flag's clear), so the panic finds the value the binding's and drops it once.
// d709 (main 0d1e4d1 + github#1784 + #709): accepted, LeakSanitizer: the moved bindings, their destructors never run.
// map: §7.2 | A2 | runs-clean | - | agora #741 guard: a binding moved into a struct literal is dropped once when a later field panics
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_print `` ) } }

: Two { Bomb first Bomb mid Bomb last }
: Pair { Bomb a Bomb b }
: Outer { Pair p Bomb z }

@ bomb i k → Bomb { ^ @ Bomb { ( string_from `a tag long enough for the heap` ) k } }

@ late i on → Bomb { ? == on 1 { ( panic `panic while building` ) } {} ^ ( bomb 9 ) }

@ lookp Pair p → i { ^ ( string_len . . p a tag ) }

@ flat → v { : Bomb b ( bomb 0 ) : Two t @ Two { b ( bomb 1 ) ( late 1 ) } }

@ nested → v { : Bomb b ( bomb 2 ) : Outer o @ Outer { @ Pair { b ( bomb 3 ) } ( late 1 ) } }

@ to_reader → v { : Bomb b ( bomb 4 ) ( lookp @ Pair { b ( late 1 ) } ) }

@ in_option → v { : Bomb b ( bomb 5 ) : ?Pair t @ ?Pair { T @ Pair { b ( late 1 ) } } }

@ main → i {
    : !v PanicInfo a ( recover \ → v { ( flat ) } )
    : !v PanicInfo b ( recover \ → v { ( nested ) } )
    : !v PanicInfo c ( recover \ → v { ( to_reader ) } )
    : !v PanicInfo d ( recover \ → v { ( in_option ) } )
    ^ 0
}
