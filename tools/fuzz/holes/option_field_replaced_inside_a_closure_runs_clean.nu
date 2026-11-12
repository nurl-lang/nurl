// option_field_replaced_inside_a_closure_runs_clean: a closure replaces, three times, an option field of a struct it captured by pointer, and once an option field of a struct of its own; the struct is dropped afterwards.
// Guard for agora #731: inside a closure an option / result field's old value is dropped under the capture's owner flag (`__outer_owned`), as a handle field's is — the gate on the closure depth is gone.
// main 70f7232: accepted, LeakSanitizer: every replaced value but the last.
// map: §7.2 | A2 | runs-clean | - | agora #731 guard: a field store inside a closure drops the option value it replaces, once
$ `stdlib/core/string.nu`

: Bomb { String tag i n }

% Drop Bomb { @ drop Bomb b → v { ( nurl_print `` ) } }

@ bomb i n → Bomb { ^ @ Bomb { ( string_from `a value long enough for the heap` ) n } }

: Holder { ? Bomb o i n }

@ main → i {
    : ~ Holder h @ Holder { @ ?Bomb { T ( bomb 0 ) } 0 }
    : ( @ v ) set \ → v { = . h o @ ?Bomb { T ( bomb 1 ) } }
    ( set ) ( set ) ( set )
    : ( @ v ) own \ → v { : ~ Holder l @ Holder { @ ?Bomb { T ( bomb 2 ) } 0 } = . l o @ ?Bomb { T ( bomb 3 ) } }
    ( own )
    ^ 0
}
