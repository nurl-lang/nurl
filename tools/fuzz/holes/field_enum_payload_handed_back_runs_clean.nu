// field_enum_payload_handed_back_runs_clean: a String payload of an enum held in a field of a local struct, handed back out of a `??` arm (`?? . w en { Three x s y → { ^ s } }`, by name, as a join's value, as a field of a boxed payload).
// Guard for agora #641: no take moves a payload out of an enum in a field, so the arm is lent it and the struct drops it on the way out; the caller gets its own copy, and is told it owns it. Before, the caller got the struct's own String: freed by the struct's drop, read and freed again by the caller; a boxed payload's field was copied but answered as lent, and the copy leaked.
// main 37334be: accepted, heap-use-after-free in the caller (by name and as a join); the boxed field's copy leaks.
// map: §7.6 | A2 | runs-clean | - | agora #641 guard: a payload of an enum in a local struct's field handed back out of an arm is the caller's own copy (by name, a join, a boxed payload's field)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: Pair { Bomb p String q }

: | E { Zero i Three Bomb String Bomb Boxed Pair }

: W { E en i k }

@ mkw → W { ^ @ W { @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } 1 } }

@ by_name → String {
    : W w ( mkw )
    ?? . w en {
        Zero n → {}
        Three x s y → { ^ s }
        Boxed p → {}
    }
    ^ ( string_from `none` )
}

@ by_join → String {
    : W w ( mkw )
    ^ ?? . w en {
        Zero n → ( string_from `none` )
        Three x s y → s
        Boxed p → . p q
    }
}

@ boxed_field → String {
    : W w @ W { @ E { Boxed @ Pair { ( bomb `bp` ) ( string_from `bq, long enough for the heap` ) } } 1 }
    ?? . w en {
        Zero n → {}
        Three x s y → {}
        Boxed p → { ^ . p q }
    }
    ^ ( string_from `none` )
}

@ main → i {
    : String a ( by_name )
    ( nurl_println ( string_data a ) )
    : String b ( by_join )
    ( nurl_println ( string_data b ) )
    : String c ( boxed_field )
    ( nurl_println ( string_data c ) )
    ^ 0
}
