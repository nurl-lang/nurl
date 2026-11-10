// slice_owned_panic.nu — a panic that unwinds over an owned slice releases
// it, elements and buffer (agora #509): a binding, and a temporary in the
// argument list of the call that panicked. The sanitizer run holds it.
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/core/vec.nu`

// #509: a literal of Strings bound in a function a panic unwinds
@ lit_boom i k → i {
    : [String sl [String | ( string_from `a string in a slice literal when a panic unwinds over it` )]
    ? > k 0 { ( panic `boom` ) } {}
    ~ x sl { ( nurl_println ( string_data x ) ) }
    ^ 0
}
@ run_lit → i {
    : !v PanicInfo r ( recover \ → v { : i _n ( lit_boom 1 ) } )
    ?? r { T _ → {} F p → { ( nurl_println `recovered` ) ( panic_info_free p ) } }
    ^ 0
}

// a call's result and a literal in the argument list of a call that panics
@ arg_boom i n [String a → v { ? > n 0 { ( panic `boom` ) } {} }
@ arg_mk → [String { ^ [String | ( string_from `a long enough string to be on the heap, one` )] }
@ run_arg → i {
    : [String keep ( arg_mk )
    : !v PanicInfo r ( recover \ → v { ( arg_boom 1 ( arg_mk ) ) } )
    ?? r { T u → { ( nurl_println `no panic` ) } F e → { ( nurl_println `recovered` ) } }
    : !v PanicInfo r2 ( recover \ → v { : [String loc ( arg_mk ) ( arg_boom 1 [String | ( string_from `a literal's long string on the heap, yes` )] ) } )
    ?? r2 { T u → { ( nurl_println `no panic` ) } F e → { ( nurl_println `recovered` ) } }
    ^ 0 }

@ main → i {
    ( nurl_println `lit` ) ( run_lit )
    ( nurl_println `arg` ) ( run_arg )
    ^ 0
}
