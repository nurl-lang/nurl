// panic_reclaims_closure_envs.nu — a panic that unwinds past a closure
// drops its env, as the closure's scope exit would have (agora #131).
//
// A closure's env was never in the panic journal: a literal handed to a
// call, a bound closure, a `sink` closure parameter, a closure a call
// returned, a struct literal's closure and String fields — each was
// dropped after the call or at its scope's exit, and a panic skipped both.
// Every closure binding is now in its function's closure frame table, and
// an argument's closure temporaries and a literal argument's owned fields
// are journaled while the call runs. The leaks are pinned by the
// sanitizer corpus (LSan); the output pins the normal paths, which must
// not drop anything twice.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Job { String name ( @ i ) f }

@ boom → v { ( nurl_panic `boom` ) }

@ run ( @ v ) f → v { ( boom ) }

@ run_sink sink ( @ v ) f → v { ( boom ) }

@ run_job Job j i k → i {
    ? == k 2 { ( boom ) } {}
    : ( @ i ) g . j f
    ^ + ( string_len . j name ) ( g )
}

@ mk → ( @ v ) {
    : String s ( text )
    ^ \ → v { ( nurl_println ( string_data s ) ) }
}

@ text → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ literal → v { : String a ( text ) ( run \ → v { ( nurl_println ( string_data a ) ) } ) }

@ bound → v {
    : String a ( text )
    : ( @ v ) f \ → v { ( nurl_println ( string_data a ) ) }
    ( run f )
}

@ to_sink → v {
    : String a ( text )
    : ( @ v ) f \ → v { ( nurl_println ( string_data a ) ) }
    ( run_sink f )
}

@ returned → v { ( run ( mk ) ) }

@ in_a_loop → v {
    : ~ i k 0
    ~ < k 3 {
        : String a ( text )
        : ( @ v ) f \ → v { ( nurl_println ( string_data a ) ) }
        ? == k 2 { ( run f ) } {}
        = k + k 1
    }
}

@ from_inside → v {
    : String a ( text )
    : ( @ v ) f \ → v { ( boom ) }
    ( f )
}

@ main → i {
    : !v PanicInfo r1 ( recover \ → v { ( literal ) } )
    : !v PanicInfo r2 ( recover \ → v { ( bound ) } )
    : !v PanicInfo r3 ( recover \ → v { ( to_sink ) } )
    : !v PanicInfo r4 ( recover \ → v { ( returned ) } )
    : !v PanicInfo r5 ( recover \ → v { ( in_a_loop ) } )
    : !v PanicInfo r6 ( recover \ → v { ( from_inside ) } )
    ( nurl_println `six recovered` )
    // A literal argument's String and closure: dropped once on the normal
    // path, reclaimed by the journal on the panicking one.
    : String cap ( string_from `captured` )
    : ~ i k 0
    : ~ i total 0
    ~ < k 4 {
        : ~ i got 0
        : !v PanicInfo r ( recover \ → v { = got ( run_job @ Job { ( text ) \ → i { ^ ( string_len cap ) } } k ) } )
        = total + total got
        = k + k 1
    }
    ( nurl_print `total ` ) ( nurl_println_int total )
    ^ 0
}
