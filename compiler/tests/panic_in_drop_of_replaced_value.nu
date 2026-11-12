// panic_in_drop_of_replaced_value.nu — a value given a new one (`= b ( new
// )`, `= . h f ( new )`) whose OLD value's destructor panics (Agora #621).
//
// The old value leaves its slot before its destructor runs, as a value at
// its scope's end does: the slot holds the new value from the store on, so
// the panic finds the new value where it belongs — the unwind drops it,
// once — and the old value's destructor releases what it still holds. Before,
// the old value was dropped in place and the new one stored after: the
// unwind dropped the old value a second time (its fields were already the
// destructor's own — a heap-use-after-free under ASan) and the new value,
// in no slot yet, was lost.

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

: Holder { Bomb b i n }
: Outer { Holder h i m }
: VecHolder { ( Vec Bomb ) v i n }
: OptHolder { ? Bomb o i n }
: CloHolder { ( @ i ) f i n }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

@ bombs s tag i boom → ( Vec Bomb ) {
    : ~ ( Vec Bomb ) w ( vec_new [Bomb] )
    ( vec_push [Bomb] w ( bomb tag boom ) )
    ^ w
}

// A binding.
@ binding → v {
    : ~ Bomb b ( bomb `binding.old` 1 )
    = b ( bomb `binding.new` 0 )
    ( nurl_println `not reached` )
}

// A Vec binding whose old elements' second destructor panics: the rest of
// the old elements are dropped (#608), and the new Vec once.
@ vec_binding → v {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `vec.old-1` 0 ) )
    ( vec_push [Bomb] v ( bomb `vec.old-2` 1 ) )
    ( vec_push [Bomb] v ( bomb `vec.old-3` 0 ) )
    = v ( bombs `vec.new` 0 )
    ( nurl_println `not reached` )
}

// An option binding.
@ option → v {
    : ~ ? Bomb o @ ?Bomb { T ( bomb `option.old` 1 ) }
    = o @ ?Bomb { T ( bomb `option.new` 0 ) }
    ( nurl_println `not reached` )
}

// An `inout` parameter: the caller's binding holds the new value.
@ put inout Bomb slot → v { = slot ( bomb `inout.new` 0 ) }

@ inout_param → v {
    : ~ Bomb b ( bomb `inout.old` 1 )
    ( put b )
    ( nurl_println `not reached` )
}

// A field, a Vec field, an option field, a closure field, a nested field.
@ field → v {
    : ~ Holder h @ Holder { ( bomb `field.old` 1 ) 1 }
    = . h b ( bomb `field.new` 0 )
    ( nurl_println `not reached` )
}

@ vec_field → v {
    : ~ VecHolder h @ VecHolder { ( bombs `vfield.old` 1 ) 1 }
    = . h v ( bombs `vfield.new` 0 )
    ( nurl_println `not reached` )
}

@ option_field → v {
    : ~ OptHolder h @ OptHolder { @ ?Bomb { T ( bomb `ofield.old` 1 ) } 1 }
    = . h o @ ?Bomb { T ( bomb `ofield.new` 0 ) }
    ( nurl_println `not reached` )
}

@ closure_field → v {
    : Bomb c1 ( bomb `cfield.old` 1 )
    : ~ CloHolder h @ CloHolder { \ → i { ^ . c1 boom } 1 }
    : Bomb c2 ( bomb `cfield.new` 0 )
    = . h f \ → i { ^ . c2 boom }
    ( nurl_println `not reached` )
}

@ nested_field → v {
    : ~ Outer o @ Outer { @ Holder { ( bomb `nested.old` 1 ) 1 } 2 }
    = . . o h b ( bomb `nested.new` 0 )
    ( nurl_println `not reached` )
}

// In a loop: the third round's old value panics.
@ looped → v {
    : ~ Bomb b ( bomb `loop.0` 0 )
    : ~ i k 0
    ~ < k 4 {
        = b ( bomb ( nurl_str_cat `loop.` ( nurl_str_int + k 1 ) ) ? == k 2 1 0 )
        = k + k 1
    }
    ( nurl_println `not reached` )
}

// No panic: the old value goes at the assignment, the new one at the end.
@ quiet → v {
    : ~ Bomb b ( bomb `quiet.old` 0 )
    = b ( bomb `quiet.new` 0 )
    ( nurl_println `quiet: assigned` )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `binding` \ → v { ( binding ) } )
    ( run `vec_binding` \ → v { ( vec_binding ) } )
    ( run `option` \ → v { ( option ) } )
    ( run `inout_param` \ → v { ( inout_param ) } )
    ( run `field` \ → v { ( field ) } )
    ( run `vec_field` \ → v { ( vec_field ) } )
    ( run `option_field` \ → v { ( option_field ) } )
    ( run `closure_field` \ → v { ( closure_field ) } )
    ( run `nested_field` \ → v { ( nested_field ) } )
    ( run `looped` \ → v { ( looped ) } )
    ( run `quiet` \ → v { ( quiet ) } )
    // A binding owned outside the recover extent, given a new value inside
    // it: after the recover it holds the new value, usable, dropped once.
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `outer.old-1` 0 ) )
    ( vec_push [Bomb] v ( bomb `outer.old-2` 1 ) )
    ( run `outer` \ → v { = v ( bombs `outer.new` 0 ) } )
    ( nurl_println ( nurl_str_cat `outer: len ` ( nurl_str_int ( vec_len [Bomb] v ) ) ) )
    ^ 0
}
