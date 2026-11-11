// enum_with_its_own_drop_drops_its_payloads_runs_clean: an enum with a `% Drop` of its own, held by a binding, a matched temporary, a Vec, a struct, an option and a `sink` parameter.
// Guard for agora #641: its impl runs, then its drop glue drops each payload of the variant it holds, once, as a struct's glue drops its fields. Before, the impl ran and the payloads leaked; as a Vec element, a field or an option's payload the compiler's enum drop replaced the impl, which never ran; a matched temporary's arms dropped its `% Drop` payloads as their own and the rest leaked.
// main b444db1: accepted, LeakSanitizer: the payloads of every enum the impl ran for. Clean since github#1754 (c8c3f4d), which gave the enum its glue: a guard beside its probes.
// map: §7.6 | A2 | runs-clean | - | agora #641 guard: an enum with its own % Drop (bound, a matched temporary, in a Vec / a struct / an option, sunk, returned) runs its impl and then drops each payload once
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E2 { Zero2 i Three2 Bomb String Bomb One2 String }

% Drop E2 { @ drop E2 e → v { ( nurl_println `drop enum E2` ) } }

@ mk s a → E2 { ^ @ E2 { Three2 ( bomb ( nurl_str_cat a `.a` ) ) ( string_from `3s, long enough for the heap` ) ( bomb ( nurl_str_cat a `.c` ) ) } }

: Holder { String name E2 e ( Vec String ) items }

@ eat sink E2 e → v { ( nurl_println `eat` ) }

@ pass E2 e → E2 { ^ e }

@ look E2 e → v {
    ?? e {
        Zero2 n → { ( nurl_println `zero` ) }
        Three2 x s y → { ( nurl_println ( nurl_str_cat3 ( string_data . x tag ) ` ` ( string_data . y tag ) ) ) }
        One2 s → { ( nurl_println ( string_data s ) ) }
    }
}

@ main → i {
    // a binding: the task's program
    : E2 e @ E2 { Three2 ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) }
    ( nurl_println `built` )
    // a unit-like and a one-payload variant
    : E2 z @ E2 { Zero2 0 }
    : E2 o @ E2 { One2 ( string_from `one, long enough for the heap` ) }
    // matched: bound (y read), and a temporary (y unread, then read)
    ?? e {
        Zero2 n → { ( nurl_println `zero` ) }
        Three2 x s y → { ( nurl_println ( string_data . y tag ) ) }
        One2 s → { ( nurl_println ( string_data s ) ) }
    }
    ?? ( mk `t1` ) {
        Zero2 n → { ( nurl_println `zero` ) }
        Three2 x s y → { ( nurl_println ( string_data . x tag ) ) }
        One2 s → { ( nurl_println ( string_data s ) ) }
    }
    ?? ( mk `t2` ) {
        Zero2 n → { ( nurl_println `zero` ) }
        Three2 x s y → { ( nurl_println ( string_data . y tag ) ) }
        One2 s → { ( nurl_println ( string_data s ) ) }
    }
    ( look e )
    // a Vec element, a struct field, an option's payload
    : ~ ( Vec E2 ) v ( vec_new [E2] )
    ( vec_push [E2] v ( mk `vec` ) )
    ( vec_push [E2] v @ E2 { Zero2 1 } )
    : Holder h @ Holder { ( string_from `a name on the heap, long enough` ) ( mk `field` ) ( vec_new [String] ) }
    : ?E2 opt @ ?E2 { T ( mk `opt` ) }
    // handed to a `sink`, and through a function that hands it back
    : E2 a ( mk `sunk` )
    ( eat a )
    : E2 b ( pass ( mk `passed` ) )
    ( nurl_println `end` )
    ^ 0
}
