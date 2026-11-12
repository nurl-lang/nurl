// struct_literal_drop_and_closure_fields.nu — struct literals with a `%
// Drop` field (Agora #642): beside a closure field, passed straight to a
// borrowing parameter, and built while a later field's expression panics.
//
// 1. A struct with a `% Drop` field has a drop of its own (the compiler
//    writes it), which releases a closure field's environment with the
//    rest; the field was registered for a release of its own as well, and
//    the env was freed twice (heap-use-after-free) — also when the struct
//    moved through a Vec (vec_pop, then vec_push).
// 2. Such a literal handed straight to a parameter that only reads it was
//    dropped after the call only in its handle fields: the `% Drop` fields
//    never ran their destructors.
// 3. A field the literal made is the literal's from then on; while a later
//    field's expression ran, the literal was in no journal entry, and a
//    panic there left the field to nobody.
// 4. A binding moved into the literal gave its value up at its field, the
//    same way: a later field's panic dropped neither the binding nor the
//    literal (Agora #741). It hands it over at the `}`.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb {
    @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) }
}

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: C { Bomb x ( @ i ) f }

: S5 { Bomb x String m Bomb y }

: Mixed { String a ( @ i ) f ? Bomb o Bomb last }

@ look S5 s → i { ^ ( string_len . s m ) }

@ lookc C c → i { : ( @ i ) g . c f ^ ( g ) }

@ late i on → Bomb { ? == on 1 { ( panic `panic while building` ) } {} ^ ( bomb `late` 0 ) }

@ beside_closure → v {
    : String other ( string_from `a captured string, long enough for the heap` )
    : ( @ i ) clo \ → i { ^ ( string_len other ) }
    : C h @ C { ( bomb `beside` 0 ) clo }
    : String other2 ( string_from `another captured string, long enough for the heap` )
    : ~ C h2 @ C { ( bomb `inline` 0 ) \ → i { ^ ( string_len other2 ) } }
    // (A closure field replaced: the env it held goes, once.)
    : String other3 ( string_from `a third captured string, long enough for the heap` )
    = . h2 f \ → i { ^ ( string_len other3 ) }
    ( nurl_println `beside_closure: built` )
}

@ through_a_vec → v {
    : String other ( string_from `a captured string, long enough for the heap` )
    : ( @ i ) clo \ → i { ^ ( string_len other ) }
    : ~ ( Vec C ) v ( vec_new [C] )
    ( vec_push [C] v @ C { ( bomb `moved` 0 ) clo } )
    : ?C p ( vec_pop [C] v )
    ?? p { T c → { ( vec_push [C] v c ) } F → {} }
    ( nurl_println ( nurl_str_cat `through_a_vec: len ` ( nurl_str_int ( vec_len [C] v ) ) ) )
}

@ to_a_reader → v {
    : i n ( look @ S5 { ( bomb `read.x` 0 ) ( string_from `m, long enough for the heap` ) ( bomb `read.y` 0 ) } )
    : String other ( string_from `a captured string, long enough for the heap` )
    : i k ( lookc @ C { ( bomb `read.c` 0 ) \ → i { ^ ( string_len other ) } } )
    ( nurl_println ( nurl_str_cat3 `to_a_reader: ` ( nurl_str_int n ) ( nurl_str_cat ` ` ( nurl_str_int k ) ) ) )
}

: Two { Bomb first Bomb mid Bomb last }

@ panic_mid_literal → v {
    : Two t @ Two { ( bomb `first` 0 ) ( late 1 ) ( bomb `last` 0 ) }
    ( nurl_println `not reached` )
}

@ panic_mid_mixed → v {
    : String other ( string_from `a captured string, long enough for the heap` )
    : Mixed m @ Mixed { ( string_from `a mixed string, long enough for the heap` ) \ → i { ^ ( string_len other ) } @ ?Bomb { T ( bomb `mixed.opt` 0 ) } ( late 1 ) }
    ( nurl_println `not reached` )
}

: Pair { Bomb a Bomb b }
: Outer { Pair p Bomb z }

@ moved_binding_then_panic → v {
    : Bomb b ( bomb `moved` 0 )
    : Two t @ Two { b ( bomb `made` 0 ) ( late 1 ) }
    ( nurl_println `not reached` )
}

// …the binding in a nested literal, the panic in the outer one's field.
@ moved_into_nested_then_panic → v {
    : Bomb b ( bomb `nested.moved` 0 )
    : Outer o @ Outer { @ Pair { b ( bomb `nested.made` 0 ) } ( late 1 ) }
    ( nurl_println `not reached` )
}

// …a literal handed to a reader, the binding its first field.
@ lookp Pair p → i { ^ ( string_len . . p a tag ) }

@ moved_into_argument_then_panic → v {
    : Bomb b ( bomb `arg.moved` 0 )
    ( lookp @ Pair { b ( late 1 ) } )
    ( nurl_println `not reached` )
}

// …and with no panic the binding's value is the literal's, dropped once
// with it.
@ moved_binding_no_panic → v {
    : Bomb b ( bomb `kept.moved` 0 )
    : Two t @ Two { b ( bomb `kept.made` 0 ) ( late 0 ) }
    ( nurl_println `built` )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( beside_closure )
    ( through_a_vec )
    ( to_a_reader )
    ( run `panic_mid_literal` \ → v { ( panic_mid_literal ) } )
    ( run `panic_mid_mixed` \ → v { ( panic_mid_mixed ) } )
    ( run `moved_binding_then_panic` \ → v { ( moved_binding_then_panic ) } )
    ( run `moved_into_nested_then_panic` \ → v { ( moved_into_nested_then_panic ) } )
    ( run `moved_into_argument_then_panic` \ → v { ( moved_into_argument_then_panic ) } )
    ( run `moved_binding_no_panic` \ → v { ( moved_binding_no_panic ) } )
    ^ 0
}
