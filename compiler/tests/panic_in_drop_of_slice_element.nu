// panic_in_drop_of_slice_element.nu — an element's destructor panics while
// an owned slice releases its elements (Agora #545; the slice sibling of
// Agora #608, panic_in_drop_of_vec_element.nu).
//
// An owned slice `[T` is its buffer and a length, and drops its elements
// and then the buffer. Where an element's drop may run a destructor of the
// program's own, the runtime does both (nurl_slice_drop_dtor) with the
// continuation a Vec's release has: a panic in one element's destructor
// goes on with the elements after it, in index order and once each, frees
// the buffer, and only then goes on to its `recover`.
//
// `field` / `rows` / `nested` / `opt`: the slice inside a struct, a struct
// in a Vec, another slice and an option. A struct with a `[Bomb` field
// cannot be copied, so it is dropped field by field like one holding a
// `( Vec Bomb )` — it was dropped by nobody, panic or none (`plain`).
// `every_one`: every element's destructor panics; each is caught where the
// release goes on, and the first panic keeps its message.

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

@ three s a s b s c i boom → [Bomb { ^ [Bomb | ( bomb a 0 ) ( bomb b boom ) ( bomb c 0 )] }

// The slice's own drop, at its binding's end.
@ whole → v {
    : [Bomb a ( three `a` `b` `c` 1 )
    ( nurl_println `whole: built` )
}

// Two of the elements panic: a panic inside the first one's drain. The
// first panic — the cause — keeps its message.
@ two_bombs → v {
    : [Bomb a [Bomb | ( bomb `a` 0 ) ( bomb `b` 1 ) ( bomb `c` 1 ) ( bomb `d` 0 )]
    ( nurl_println `two_bombs: built` )
}

// The first and the last element, beside another owner in the scope.
@ first_last → v {
    : [Bomb a [Bomb | ( bomb `a` 1 ) ( bomb `b` 0 ) ( bomb `c` 1 )]
    : String keep ( string_from `kept` )
    ( nurl_println ( nurl_str_cat `first_last: built, ` ( string_data keep ) ) )
}

: Holder { [Bomb items i n }

// A struct's slice field: the struct is dropped field by field.
@ field → v {
    : Holder h @ Holder { ( three `a` `b` `c` 1 ) 3 }
    ( nurl_println `field: built` )
}

// …and with no panic at all, outside any recover extent.
@ plain → v {
    : Holder h @ Holder { ( three `p` `q` `r` 0 ) 3 }
    ( nurl_println ( nurl_str_cat `plain: built ` ( nurl_str_int . h n ) ) )
}

// A Vec of such structs: the Vec's release goes on with the next struct,
// the slice's with the next element.
@ rows → v {
    : ~ ( Vec Holder ) w ( vec_new [Holder] )
    ( vec_push [Holder] w @ Holder { ( three `a` `b` `c` 1 ) 3 } )
    ( vec_push [Holder] w @ Holder { ( three `d` `e` `f` 0 ) 3 } )
    ( nurl_println `rows: built` )
}

// A slice of slices: the inner release is left by the panic, then the
// outer one goes on.
@ nested → v {
    : [[Bomb a [[Bomb | ( three `a` `b` `c` 1 ) ( three `d` `e` `f` 0 )]
    ( nurl_println `nested: built` )
}

@ opt → v {
    : ?[Bomb o @ ?[Bomb { T ( three `a` `b` `c` 1 ) }
    ( nurl_println `opt: built` )
}

: ~ i g_ticks 0

: Tick { i id }

% Drop Tick {
    @ drop Tick t → v {
        = g_ticks + g_ticks 1
        ( panic `tick` )
    }
}

// Every destructor panics.
@ every_one → v {
    : [Tick a [Tick | @ Tick { 0 } @ Tick { 1 } @ Tick { 2 } @ Tick { 3 } @ Tick { 4 } @ Tick { 5 } @ Tick { 6 } @ Tick { 7 }]
    ( nurl_println `every_one: built` )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `whole` \ → v { ( whole ) } )
    ( run `two_bombs` \ → v { ( two_bombs ) } )
    ( run `first_last` \ → v { ( first_last ) } )
    ( run `field` \ → v { ( field ) } )
    ( plain )
    ( run `plain` \ → v { ( plain ) } )
    ( run `rows` \ → v { ( rows ) } )
    ( run `nested` \ → v { ( nested ) } )
    ( run `opt` \ → v { ( opt ) } )
    ( run `every_one` \ → v { ( every_one ) } )
    ( nurl_println ( nurl_str_cat `ticks: ` ( nurl_str_int g_ticks ) ) )
    ^ 0
}
