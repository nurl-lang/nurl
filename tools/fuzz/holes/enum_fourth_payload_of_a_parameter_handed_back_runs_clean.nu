// enum_fourth_payload_of_a_parameter_handed_back_runs_clean: the fourth payload of a variant, of a `% Drop` type, handed back by name out of a `??` over a parameter the function does not take (`?? e { Four a b c d → { ^ d } }`).
// Guard for agora #641: it is the caller's own value, lent back as part of that parameter, as the first three payloads are (agora #462): the caller's binding of the result drops nothing and the enum drops it once. The fourth and later payloads had no record of the binding they were matched out of (`__plroot`), so the function answered "owned" and the caller's binding and the enum both dropped it.
// main 37334be: accepted, heap-use-after-free in drop__Bomb.
// map: §7.6 | A2 | runs-clean | - | agora #641 guard: the fourth % Drop payload of a parameter's enum handed back is lent, as the first three are (the caller's binding and the enum dropped it twice)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Four Bomb Bomb Bomb Bomb }

@ mk4 → E { ^ @ E { Four ( bomb `4a` ) ( bomb `4b` ) ( bomb `4c` ) ( bomb `4d` ) } }

@ third E e → Bomb {
    ?? e {
        Zero n → { ^ ( bomb `z` ) }
        Four a b c d → { ^ c }
    }
}

@ last E e → Bomb {
    ?? e {
        Zero n → { ^ ( bomb `z` ) }
        Four a b c d → { ^ d }
    }
}

@ main → i {
    : E e ( mk4 )
    : Bomb x ( third e )
    ( nurl_println ( nurl_str_cat `third: ` ( string_data . x tag ) ) )
    : Bomb y ( last e )
    ( nurl_println ( nurl_str_cat `last: ` ( string_data . y tag ) ) )
    ^ 0
}
