// enum_own_drop_glue.nu — an enum with a `% Drop` of its own (Agora #641;
// formal/CLAIM.md, `ImplGlueOK` over a struct or an enum).
//
// It is dropped as a struct with one is: its impl runs, then the payloads
// of the variant that is there are dropped by the enum's glue, once each —
// as a binding, a Vec's element, a struct's field and a matched temporary
// alike. Before, a binding ran the impl and never dropped the payloads
// (they leaked), and as an element, a field or a temporary the impl never
// ran at all.
//
// The enum stays whole for its destructor: a `??` arm is lent its payloads
// and none is taken out of it. A payload handed back out of an enum the
// function keeps is the caller's own copy (`third`, `boxed_field`); the
// enum drops its payload as before. A panic in the impl, or in a payload's
// destructor, still drops what is left (`impl_panics`, `payload_panics`).

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb {
    @ drop Bomb b → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) )
        ? == . b boom 1 { ( panic ( nurl_str_cat `panic in drop ` ( string_data . b tag ) ) ) } {}
    }
}

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Pair { Bomb p String q }

: | E { Zero i Three Bomb String Bomb Boxed Pair }

// The impl reads its receiver's payloads: they are still there.
% Drop E {
    @ drop E e → v {
        ?? e {
            Zero n → { ( nurl_println `drop E Zero` ) }
            Three x s y → { ( nurl_println ( nurl_str_cat `drop E Three ` ( string_data s ) ) ) }
            Boxed p → { ( nurl_println ( nurl_str_cat `drop E Boxed ` ( string_data . p q ) ) ) }
        }
    }
}

@ mk3 s a s c i boom → E { ^ @ E { Three ( bomb a boom ) ( string_from `the string payload, on the heap` ) ( bomb c 0 ) } }

@ mkb → E { ^ @ E { Boxed @ Pair { ( bomb `bp` 0 ) ( string_from `the boxed field, on the heap` ) } } }

: Holder { E e String s }

@ bound → v {
    : E e ( mk3 `a` `c` 0 )
    ( nurl_println `bound: built` )
}

@ element_and_field → v {
    : ~ ( Vec E ) v ( vec_new [E] )
    ( vec_push [E] v ( mk3 `va` `vc` 0 ) )
    ( vec_push [E] v @ E { Zero 4 } )
    : Holder h @ Holder { ( mk3 `ha` `hc` 0 ) ( string_from `the holder's own string, on the heap` ) }
    ( nurl_println `element_and_field: built` )
}

@ temporary → v {
    ?? ( mk3 `ta` `tc` 0 ) {
        Zero n → { ( nurl_println `zero` ) }
        Three x s y → { ( nurl_println ( nurl_str_cat3 `temporary: ` ( string_data . x tag ) ( string_data . y tag ) ) ) }
        Boxed p → { ( nurl_println `boxed` ) }
    }
    ( nurl_println `temporary: after the match` )
}

// A payload handed back: a copy, the enum keeps its own.
@ third → String {
    : E e ( mk3 `ra` `rc` 0 )
    ?? e {
        Zero n → {}
        Three x s y → { ^ s }
        Boxed p → {}
    }
    ^ ( string_from `no payload` )
}

@ joined → String {
    : E e ( mk3 `ja` `jc` 0 )
    ^ ?? e {
        Zero n → ( string_from `no payload` )
        Three x s y → s
        Boxed p → . p q
    }
}

@ boxed_field → String {
    : E e ( mkb )
    ?? e {
        Zero n → {}
        Three x s y → {}
        Boxed p → { ^ . p q }
    }
    ^ ( string_from `no payload` )
}

@ handed_back → v {
    : String a ( third )
    ( nurl_println ( nurl_str_cat `third: ` ( string_data a ) ) )
    : String b ( joined )
    ( nurl_println ( nurl_str_cat `joined: ` ( string_data b ) ) )
    : String c ( boxed_field )
    ( nurl_println ( nurl_str_cat `boxed_field: ` ( string_data c ) ) )
}

@ payload_panics → v {
    : E e ( mk3 `pa` `pc` 1 )
    ( nurl_println `payload_panics: built` )
}

: | P { PA Bomb String Bomb PB i }

% Drop P {
    @ drop P p → v {
        ( nurl_println `drop P` )
        ( panic `panic in drop P` )
    }
}

@ impl_panics → v {
    : P p @ P { PA ( bomb `ia` 0 ) ( string_from `a string the impl's panic must not leak` ) ( bomb `ic` 0 ) }
    ( nurl_println `impl_panics: built` )
}

@ replaced → v {
    : ~ E e ( mk3 `old-a` `old-c` 0 )
    = e @ E { Zero 1 }
    ( nurl_println `replaced: new value in` )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `bound` \ → v { ( bound ) } )
    ( run `element_and_field` \ → v { ( element_and_field ) } )
    ( run `temporary` \ → v { ( temporary ) } )
    ( run `handed_back` \ → v { ( handed_back ) } )
    ( run `payload_panics` \ → v { ( payload_panics ) } )
    ( run `impl_panics` \ → v { ( impl_panics ) } )
    ( run `replaced` \ → v { ( replaced ) } )
    ^ 0
}
