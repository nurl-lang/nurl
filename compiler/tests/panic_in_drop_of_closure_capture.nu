// panic_in_drop_of_closure_capture.nu — a value a closure captured, or a
// trait object boxed, whose destructor panics when its holder is released
// (Agora #645, #650; formal/CLAIM.md, the closure's drop method).
//
// The env's drop method releases its captures in order and the runtime
// frees the env's block when it returns; a trait object's drop runs the
// boxed value's destructor and frees the box. A panic in one of those
// destructors left the captures after it, the block (the box) and — where
// the journal's elision took the env's release for a call no panic can
// start in — the bindings and fields around it to no one: they leaked
// (LeakSanitizer, run_san_tests.sh). Now the method journals what is
// still to go, as a struct's drop glue does, and the release of an env
// may panic exactly when one of the program's env methods may.
//
// `fields_after`: a struct's fields after a closure field. `alive_across`:
// a binding whose scope ends in an env's release only. `two_captures`:
// the capture after the one that panics, and a String capture.
// `nested`: a closure that captured a closure. `boxed`: a trait object.

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

: C { String a ( @ i ) f String s ( Vec String ) w }

@ mkc i boom → C {
    : Bomb cap ( bomb `cap` boom )
    : ( @ i ) clo \ → i { ^ ( string_len . cap tag ) }
    ^ @ C { ( string_from `a field before the closure, on the heap` ) clo ( string_from `a field after the closure, on the heap` ) ( vec_new [String] ) }
}

@ fields_after → v {
    : C h ( mkc 1 )
    ( nurl_println `fields_after: built` )
}

@ mk sink Bomb b → ( @ i ) { ^ \ → i { ^ ( string_len . b tag ) } }

@ alive_across → v {
    : String t ( string_from `a binding alive across the env's release` )
    : ( @ i ) f ( mk ( bomb `old` 1 ) )
    ( nurl_println ( nurl_str_cat `alive_across: ` ( nurl_str_int + ( f ) ( string_len t ) ) ) )
}

@ two_captures → v {
    : Bomb a ( bomb `first` 1 )
    : Bomb b ( bomb `second` 0 )
    : String s ( string_from `a captured string, on the heap` )
    : ( @ i ) f \ → i { ^ + ( string_len . a tag ) + ( string_len . b tag ) ( string_len s ) }
    : ( @ i ) g f
    ( nurl_println ( nurl_str_cat `two_captures: ` ( nurl_str_int ( g ) ) ) )
}

@ outer_of sink ( @ i ) inner → ( @ i ) { ^ \ → i { ^ + ( inner ) 1 } }

@ nested → v {
    : ( @ i ) f ( outer_of ( mk ( bomb `inner` 1 ) ) )
    ( nurl_println ( nurl_str_cat `nested: ` ( nurl_str_int ( f ) ) ) )
}

% Speaker [T] {
    @ speak T self → i
}

: Dog { Bomb b String name }

% Speaker Dog { @ speak Dog d → i { ^ ( string_len . d name ) } }

@ boxed → v {
    : Dog d @ Dog { ( bomb `dog` 1 ) ( string_from `rex, long enough for the heap` ) }
    : %Speaker s ( dyn Speaker d )
    ( nurl_println ( nurl_str_cat `boxed: ` ( nurl_str_int ( speak s ) ) ) )
}

// No destructor panics: the same shapes release as before.
@ quiet → v {
    : C h ( mkc 0 )
    : ( @ i ) f ( outer_of ( mk ( bomb `quiet` 0 ) ) )
    ( nurl_println ( nurl_str_cat `quiet: ` ( nurl_str_int ( f ) ) ) )
}

@ run s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ main → i {
    ( run `fields_after` \ → v { ( fields_after ) } )
    ( run `alive_across` \ → v { ( alive_across ) } )
    ( run `two_captures` \ → v { ( two_captures ) } )
    ( run `nested` \ → v { ( nested ) } )
    ( run `boxed` \ → v { ( boxed ) } )
    ( run `quiet` \ → v { ( quiet ) } )
    ^ 0
}
