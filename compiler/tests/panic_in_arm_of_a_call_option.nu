// panic_in_arm_of_a_call_option.nu — under `recover`, a panic in an arm of
// `?? ( f … )` over a call's fresh option or result drops the `% Drop`
// payload the arm binds (Agora #745). The payload binding was registered
// for its drop but in no journal entry: the panic found nothing standing
// for it, and it leaked. A payload lent to the arm (a `vec_get` element, a
// local option's, a parameter's) is still dropped once, by its owner.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb {
    @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) }
}

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

@ late i on → i {
    ? == on 1 { ( panic `late` ) } {}
    ^ 0
}

@ mko s tag → ?Bomb { ^ @ ?Bomb { T ( bomb tag ) } }

@ mkr s tag → !Bomb String { ^ @ !Bomb String { T ( bomb tag ) } }

@ eat sink Bomb b → i { ^ 1 }

@ option_payload → v { ?? ( mko `option` ) { T x → { : i z ( late 1 ) } F → {} } }

@ result_payload → v { ?? ( mkr `result` ) { T x → { : i z ( late 1 ) } F e → {} } }

@ moved_then_panic → v { ?? ( mko `moved` ) { T x → { : i k ( eat x ) : i z ( late 1 ) } F → {} } }

@ in_a_loop → v {
    : ~ i k 0
    ~ < k 3 {
        ?? ( mko `round` ) { T x → { : i z ( late == k 2 ) } F → {} }
        = k + k 1
    }
}

@ nested → v { ?? ( mko `outer` ) { T x → { ?? ( mko `inner` ) { T y → { : i z ( late 1 ) } F → {} } } F → {} } }

@ lent_element → v {
    : ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `element` ) )
    ?? ( vec_get [Bomb] v 0 ) { T x → { : i z ( late 1 ) } F → {} }
}

@ local_option → v {
    : ?Bomb o ( mko `local` )
    ?? o { T x → { : i z ( late 1 ) } F → {} }
}

@ no_panic → v { ?? ( mko `quiet` ) { T x → { : i z ( late 0 ) } F → {} } }

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `option_payload` \ → v { ( option_payload ) } )
    ( run `result_payload` \ → v { ( result_payload ) } )
    ( run `moved_then_panic` \ → v { ( moved_then_panic ) } )
    ( run `in_a_loop` \ → v { ( in_a_loop ) } )
    ( run `nested` \ → v { ( nested ) } )
    ( run `lent_element` \ → v { ( lent_element ) } )
    ( run `local_option` \ → v { ( local_option ) } )
    ( run `no_panic` \ → v { ( no_panic ) } )
    ^ 0
}
