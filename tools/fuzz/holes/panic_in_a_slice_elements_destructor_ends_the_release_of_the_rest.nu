// panic_in_a_slice_elements_destructor_ends_the_release_of_the_rest: the slice sibling of agora #608 — an owned slice dropped its elements in a loop of its own and then freed its buffer, with no continuation in the panic journal: an element's destructor that panicked under `recover` left the loop, and the elements after it and the buffer were nobody's (their destructors never ran; LeakSanitizer). A struct holding such a slice as a field, a Vec of those structs and a slice of slices lost the rest the same way.
// Closed: where an element's drop may run a destructor of the program's own (__drop_runs_code, which now reads through a slice), the slice's drop is the runtime's nurl_slice_drop_dtor: the elements, then the buffer, journaled with the record and the continuation a Vec's release has (agora #545).
// main (before this PR): LeakSanitizer — `drop c` never runs in `whole`, `drop c … drop f` never in `rows`.
// map: §7.2 | A2 | runs-clean | - | agora #545 (the slice sibling of #608): a panic in a slice element's destructor ended the release of the elements after it and of the buffer
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

@ whole → v {
    : [Bomb a ( three `a` `b` `c` 1 )
    ( nurl_println `whole: built` )
}

: Row { [Bomb xs }

@ rows → v {
    : ~ ( Vec Row ) w ( vec_new [Row] )
    ( vec_push [Row] w @ Row { ( three `a` `b` `c` 1 ) } )
    ( vec_push [Row] w @ Row { ( three `d` `e` `f` 0 ) } )
    ( nurl_println `rows: built` )
}

@ nested → v {
    : [[Bomb a [[Bomb | ( three `a` `b` `c` 1 ) ( three `d` `e` `f` 0 )]
    ( nurl_println `nested: built` )
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
    ( run `rows` \ → v { ( rows ) } )
    ( run `nested` \ → v { ( nested ) } )
    ^ 0
}
