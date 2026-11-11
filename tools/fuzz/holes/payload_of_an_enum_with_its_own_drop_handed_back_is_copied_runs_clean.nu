// payload_of_an_enum_with_its_own_drop_handed_back_is_copied_runs_clean: a String payload handed back out of an arm over an enum with a `% Drop` of its own that this function drops (a local, a matched temporary, a `sink` parameter, a local struct's field, a local option's payload), and one over a parameter the caller keeps.
// Guard for agora #641: nothing is taken out of such an enum (its impl and then its glue drop it whole), so the payload is a view of it: copied where this function drops the enum, lent where the caller keeps it. Before, it was handed back as it was — a lend of what the function had dropped: with the enum in a struct or an option, whose drop already released the payloads, a heap-use-after-free in the caller; with the glue, for a local and a temporary too.
// main c8c3f4d: accepted, heap-use-after-free in __nurl_clone_String: `^ s` by name is copied (github#1754), a `:` binding of the payload and a literal holding it are handed back as they were, and the caller reads what the glue released.
// map: §7.6 | A2 | runs-clean | - | agora #641 guard: a String payload of an enum with its own % Drop handed back from the arm is copied where the function drops the enum and lent where the caller keeps it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E2 { Zero2 i Three2 Bomb String Bomb One2 String }

% Drop E2 { @ drop E2 e → v { ( nurl_println `drop enum E2` ) } }

@ mk s a → E2 { ^ @ E2 { Three2 ( bomb ( nurl_str_cat a `.a` ) ) ( string_from ( nurl_str_cat a `: 3s, long enough for the heap` ) ) ( bomb ( nurl_str_cat a `.c` ) ) } }

: Holder { String name E2 e }

: W { String s i n }

@ of_param E2 e → String {
    ?? e {
        Zero2 n → { ^ ( string_from `zero` ) }
        Three2 x s y → { ^ s }
        One2 s → { ^ s }
    }
}

@ of_sink sink E2 e → String {
    ?? e {
        Zero2 n → { ^ ( string_from `zero` ) }
        Three2 x s y → { ^ s }
        One2 s → { ^ s }
    }
}

@ of_local → String {
    : E2 e ( mk `local` )
    ?? e {
        Zero2 n → { ^ ( string_from `zero` ) }
        Three2 x s y → { ^ s }
        One2 s → { ^ s }
    }
}

@ of_tmp → String {
    ?? ( mk `tmp` ) {
        Zero2 n → { ^ ( string_from `zero` ) }
        Three2 x s y → { ^ s }
        One2 s → { ^ s }
    }
}

@ of_field → String {
    : Holder h @ Holder { ( string_from `a name on the heap, long enough` ) ( mk `field` ) }
    ?? . h e {
        Zero2 n → { ^ ( string_from `zero` ) }
        Three2 x s y → { ^ s }
        One2 s → { ^ s }
    }
}

@ of_option → String {
    : ?E2 o @ ?E2 { T ( mk `option` ) }
    ?? o {
        T e → {
            ?? e {
                Zero2 n → { ^ ( string_from `zero` ) }
                Three2 x s y → { ^ s }
                One2 s → { ^ s }
            }
        }
        F → { ^ ( string_from `none` ) }
    }
}

// …bound to a name first, and inside a literal.
@ of_binding → String {
    : E2 e ( mk `binding` )
    ?? e {
        Zero2 n → { ^ ( string_from `zero` ) }
        Three2 x s y → { : String t s ^ t }
        One2 s → { ^ s }
    }
}

@ in_literal → W {
    : E2 e ( mk `literal` )
    ?? e {
        Zero2 n → { ^ @ W { ( string_from `zero` ) 0 } }
        Three2 x s y → { ^ @ W { s 3 } }
        One2 s → { ^ @ W { s 1 } }
    }
}

@ main → i {
    : E2 e ( mk `param` )
    : String a ( of_param e )
    ( nurl_println ( string_data a ) )
    : String b ( of_sink ( mk `sink` ) )
    ( nurl_println ( string_data b ) )
    : String c ( of_local )
    ( nurl_println ( string_data c ) )
    : String d ( of_tmp )
    ( nurl_println ( string_data d ) )
    : String f ( of_field )
    ( nurl_println ( string_data f ) )
    : String g ( of_option )
    ( nurl_println ( string_data g ) )
    : String h ( of_binding )
    ( nurl_println ( string_data h ) )
    : W w ( in_literal )
    ( nurl_println ( string_data . w s ) )
    ^ 0
}
