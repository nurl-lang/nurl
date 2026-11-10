// panic_in_drop_of_replaced_value.nu — the destructor of the value an
// assignment replaces panics (Agora #621; beside
// panic_in_drop_while_unwinding.nu).
//
// `= b new` gives `b` a new value and drops the one it held. The old value
// is taken out first: the new one is stored, and only then is the old one
// dropped, from a temporary. So when the old value's destructor panics the
// target already holds the new value, which the unwind — or the owner
// outside the `recover` — drops once.
//
// Before, the old value was dropped in place, with the target still
// registered in the panic journal as holding it: the unwind dropped it a
// second time (heap-use-after-free), the new value was nobody's, and an
// owner outside the recover was left holding the freed old value.
//
// Every target an assignment can write is here: a binding (a struct, a Vec,
// a slice, an option, a struct holding the value as a field), an `inout`
// parameter, a binding a closure captured, a field (of a local, through
// `inout`, nested), a slice element — and an owner outside the recover
// extent, read after it. `order`: with no panic at all nothing changes; the
// old value goes at the assignment, as it always did.

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

@ three s a s b s c i boom → ( Vec Bomb ) {
    : ~ ( Vec Bomb ) w ( vec_new [Bomb] )
    ( vec_push [Bomb] w ( bomb a 0 ) )
    ( vec_push [Bomb] w ( bomb b boom ) )
    ( vec_push [Bomb] w ( bomb c 0 ) )
    ^ w
}

// The binding itself.
@ local → v {
    : ~ Bomb a ( bomb `old` 1 )
    = a ( bomb `new` 0 )
    ( nurl_println `local: not reached` )
}

// The new value's destructor panics too, while the unwind drops it: the
// first panic keeps its message.
@ both → v {
    : ~ Bomb a ( bomb `old` 1 )
    = a ( bomb `new` 1 )
    ( nurl_println `both: not reached` )
}

// A Vec: the old Vec's release goes on with the elements after the one
// that panicked, then the new Vec is dropped.
@ vec → v {
    : ~ ( Vec Bomb ) a ( three `a` `b` `c` 1 )
    = a ( three `d` `e` `f` 0 )
    ( nurl_println `vec: not reached` )
}

// An owned slice.
@ slice → v {
    : ~ [Bomb a [Bomb | ( bomb `a` 0 ) ( bomb `b` 1 ) ( bomb `c` 0 )]
    = a [Bomb | ( bomb `d` 0 ) ( bomb `e` 0 )]
    ( nurl_println `slice: not reached` )
}

@ option → v {
    : ~ ?Bomb a @ ?Bomb { T ( bomb `old` 1 ) }
    = a @ ?Bomb { T ( bomb `new` 0 ) }
    ( nurl_println `option: not reached` )
}

: Holder { Bomb b String name }

// A struct that is dropped field by field: the old one's other fields are
// released too.
@ whole → v {
    : ~ Holder h @ Holder { ( bomb `old` 1 ) ( string_from `n` ) }
    = h @ Holder { ( bomb `new` 0 ) ( string_from `m` ) }
    ( nurl_println `whole: not reached` )
}

// A field of a local.
@ field → v {
    : ~ Holder h @ Holder { ( bomb `old` 1 ) ( string_from `n` ) }
    = . h b ( bomb `new` 0 )
    ( nurl_println `field: not reached` )
}

: Outer { Holder h i n }

@ nested → v {
    : ~ Outer o @ Outer { @ Holder { ( bomb `old` 1 ) ( string_from `n` ) } 1 }
    = . . o h b ( bomb `new` 0 )
    ( nurl_println `nested: not reached` )
}

// Through an `inout` parameter: the caller's binding holds the new value.
@ put inout Bomb p → v {
    = p ( bomb `new` 0 )
    ( nurl_println `put: not reached` )
}

@ inout_param → v {
    : ~ Bomb a ( bomb `old` 1 )
    ( put a )
    ( nurl_println `inout_param: not reached` )
}

@ put_field inout Holder p → v {
    = . p b ( bomb `new` 0 )
    ( nurl_println `put_field: not reached` )
}

@ inout_field → v {
    : ~ Holder h @ Holder { ( bomb `old` 1 ) ( string_from `n` ) }
    ( put_field h )
    ( nurl_println `inout_field: not reached` )
}

// A binding a closure captured.
@ captured → v {
    : ~ Bomb a ( bomb `old` 1 )
    : ( @ v ) f \ → v { = a ( bomb `new` 0 ) ( nurl_println `f: not reached` ) }
    ( f )
    ( nurl_println `captured: not reached` )
}

// An element of an owned slice.
@ element → v {
    : ~ [Bomb a [Bomb | ( bomb `x` 0 ) ( bomb `old` 1 ) ( bomb `z` 0 )]
    : i k 1
    = . a k ( bomb `new` 0 )
    ( nurl_println `element: not reached` )
}

// In a loop: the third value's destructor panics when the fourth replaces
// it; the fourth is the binding's.
@ looped → v {
    : ~ Bomb a ( bomb `a0` 0 )
    : ~ i k 0
    ~ < k 4 {
        = a ( bomb ( nurl_str_cat `a` ( nurl_str_int + k 1 ) ) ? == k 1 { 1 } { 0 } )
        = k + k 1
    }
    ( nurl_println `looped: not reached` )
}

// The right side reads the value it replaces.
@ next Bomb b → Bomb { ^ ( bomb ( nurl_str_cat ( string_data . b tag ) `+` ) 0 ) }

@ reads_old → v {
    : ~ Bomb a ( bomb `old` 1 )
    = a ( next a )
    ( nurl_println `reads_old: not reached` )
}

// No panic: the order is what it was.
@ order → v {
    : ~ Bomb a ( bomb `a-old` 0 )
    = a ( bomb `a-new` 0 )
    ( nurl_println `order: after a` )
    : ~ Holder h @ Holder { ( bomb `h-old` 0 ) ( string_from `n` ) }
    = . h b ( bomb `h-new` 0 )
    ( nurl_println `order: after h` )
    : ~ [Bomb sl [Bomb | ( bomb `s0` 0 ) ( bomb `s1` 0 )]
    : i k 1
    = . sl k ( bomb `s1-new` 0 )
    ( nurl_println `order: after sl` )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

// The owner is outside the recover extent: after the recover it holds the
// new value, and drops it at its own end.
@ outer → v {
    : ~ Bomb a ( bomb `old` 1 )
    ( run `outer` \ → v { = a ( bomb `new` 0 ) ( nurl_println `outer: not reached` ) } )
    ( nurl_println ( nurl_str_cat `outer: a holds ` ( string_data . a tag ) ) )
}

@ outer_vec → v {
    : ~ ( Vec Bomb ) a ( three `a` `b` `c` 1 )
    ( run `outer_vec` \ → v { = a ( three `d` `e` `f` 0 ) ( nurl_println `outer_vec: not reached` ) } )
    ( nurl_println ( nurl_str_cat `outer_vec: a holds ` ( nurl_str_int ( vec_len [Bomb] a ) ) ) )
    ~ x a { ( nurl_println ( nurl_str_cat `outer_vec: ` ( string_data . x tag ) ) ) }
}

@ main → i {
    ( run `local` \ → v { ( local ) } )
    ( run `both` \ → v { ( both ) } )
    ( run `vec` \ → v { ( vec ) } )
    ( run `slice` \ → v { ( slice ) } )
    ( run `option` \ → v { ( option ) } )
    ( run `whole` \ → v { ( whole ) } )
    ( run `field` \ → v { ( field ) } )
    ( run `nested` \ → v { ( nested ) } )
    ( run `inout_param` \ → v { ( inout_param ) } )
    ( run `inout_field` \ → v { ( inout_field ) } )
    ( run `captured` \ → v { ( captured ) } )
    ( run `element` \ → v { ( element ) } )
    ( run `looped` \ → v { ( looped ) } )
    ( run `reads_old` \ → v { ( reads_old ) } )
    ( order )
    ( run `order` \ → v { ( order ) } )
    ( outer )
    ( outer_vec )
    ^ 0
}
