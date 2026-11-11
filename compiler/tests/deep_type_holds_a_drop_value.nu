// deep_type_holds_a_drop_value.nu — a `% Drop` value nine containers deep
// in a struct's field (Agora #660).
//
// Whether a type holds a value with a `% Drop` of the program's own is a
// search over the type. It used to give up eight containers down and
// answer "none": the struct got no drop of its fields, the Bomb's
// destructor never ran and everything on the way to it leaked
// (LeakSanitizer, run_san_tests.sh). Eight deep it ran. `Mixed` goes down
// through an option, a struct, a Vec and an enum's payload instead.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

: S { i k ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) ) ) ) ) v }

@ nine → v {
    : ~ ( Vec Bomb ) v1 ( vec_new [Bomb] )
    ( vec_push [Bomb] v1 @ Bomb { ( string_from `nine deep` ) } )
    : ~ ( Vec ( Vec Bomb ) ) v2 ( vec_new [( Vec Bomb )] )
    ( vec_push [( Vec Bomb )] v2 v1 )
    : ~ ( Vec ( Vec ( Vec Bomb ) ) ) v3 ( vec_new [( Vec ( Vec Bomb ) )] )
    ( vec_push [( Vec ( Vec Bomb ) )] v3 v2 )
    : ~ ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) v4 ( vec_new [( Vec ( Vec ( Vec Bomb ) ) )] )
    ( vec_push [( Vec ( Vec ( Vec Bomb ) ) )] v4 v3 )
    : ~ ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) v5 ( vec_new [( Vec ( Vec ( Vec ( Vec Bomb ) ) ) )] )
    ( vec_push [( Vec ( Vec ( Vec ( Vec Bomb ) ) ) )] v5 v4 )
    : ~ ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) ) v6 ( vec_new [( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) )] )
    ( vec_push [( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) )] v6 v5 )
    : ~ ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) ) ) v7 ( vec_new [( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) )] )
    ( vec_push [( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) )] v7 v6 )
    : ~ ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) ) ) ) v8 ( vec_new [( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) ) )] )
    ( vec_push [( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) ) )] v8 v7 )
    : ~ ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) ) ) ) ) v9 ( vec_new [( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) ) ) )] )
    ( vec_push [( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec ( Vec Bomb ) ) ) ) ) ) ) )] v9 v8 )
    : S s @ S { 1 v9 }
    ( nurl_println `nine: built` )
}

: Leaf { i n Bomb b }

: | Wrap { None0 Has ( Vec Leaf ) }

: Mid { ? Wrap w i pad }

: Mixed { i k ( Vec ( Vec ( Vec ( Vec ( Vec ? Mid ) ) ) ) ) v }

@ mixed → v {
    : ~ ( Vec Leaf ) ls ( vec_new [Leaf] )
    ( vec_push [Leaf] ls @ Leaf { 1 @ Bomb { ( string_from `mixed` ) } } )
    : ?Mid m @ ?Mid { T @ Mid { @ ?Wrap { T @ Wrap { Has ls } } 0 } }
    : ~ ( Vec ? Mid ) a ( vec_new [? Mid] )
    ( vec_push [? Mid] a m )
    : ~ ( Vec ( Vec ? Mid ) ) b ( vec_new [( Vec ? Mid )] )
    ( vec_push [( Vec ? Mid )] b a )
    : ~ ( Vec ( Vec ( Vec ? Mid ) ) ) c ( vec_new [( Vec ( Vec ? Mid ) )] )
    ( vec_push [( Vec ( Vec ? Mid ) )] c b )
    : ~ ( Vec ( Vec ( Vec ( Vec ? Mid ) ) ) ) d ( vec_new [( Vec ( Vec ( Vec ? Mid ) ) )] )
    ( vec_push [( Vec ( Vec ( Vec ? Mid ) ) )] d c )
    : ~ ( Vec ( Vec ( Vec ( Vec ( Vec ? Mid ) ) ) ) ) e ( vec_new [( Vec ( Vec ( Vec ( Vec ? Mid ) ) ) )] )
    ( vec_push [( Vec ( Vec ( Vec ( Vec ? Mid ) ) ) )] e d )
    : Mixed x @ Mixed { 2 e }
    ( nurl_println `mixed: built` )
}

@ main → i {
    ( nine )
    ( mixed )
    ^ 0
}
