// drop_flags.nu — a `% Drop` value is dropped exactly once, whichever way
// it leaves the binding that created it (docs/MEMORY.md §7.6).
//
// Every auto-dropped binding carries a drop flag; a move clears it on its
// own path only. Before the flags, `: Res b a` registered BOTH bindings
// and dropped the one value twice (a double free), a `sink` parameter
// could not take a Drop value at all, and `= a ( mkr … )` leaked the value
// it replaced. Each `[drop N]` line below names the value being dropped,
// so a value dropped twice — or never — shows up in the output as well as
// under ASan / LeakSanitizer.

$ `stdlib/core/string.nu`

: Res { i id s p }

% Drop Res {
    @ drop Res r → v {
        ( nurl_print `[drop ` ) ( nurl_print_int . r id ) ( nurl_println `]` )
        ( release r )
    }
}

// The disposer the Drop impl delegates to: it frees the value by hand, so
// its own parameter is never dropped again.
@ release sink Res r → v { ( nurl_free . r p ) }

@ mkr i id → Res { ^ @ Res { id ( nurl_alloc 8 ) } }

@ use Res r → v { ( nurl_print `use ` ) ( nurl_print_int . r id ) ( nurl_println `` ) }

@ take sink Res r → v { ( nurl_print `take ` ) ( nurl_print_int . r id ) ( nurl_println `` ) }

// Consumes its parameter only by handing it to a sink: inferred, not declared.
@ take2 Res r → v { ( take r ) }

// Moves its parameter into a local; the caller still owns the value.
@ pass Res r → v { : Res q r ( use q ) }

@ ret1 i id → Res { : Res x ( mkr id ) ^ x }

@ main → i {
    // An alias moves the value: dropped once, through b.
    : Res a ( mkr 1 )
    : Res b a
    ( use b )

    // A declared sink, a conditional one, and an inferred one.
    : Res c ( mkr 2 )
    ( take c )
    : Res d ( mkr 3 )
    : b t T
    ? t { ( take d ) } {}
    : Res e ( mkr 4 )
    : b f F
    ? f { ( take e ) } {}
    : Res g ( mkr 5 )
    ( take2 g )

    // Returned from a helper; passed to a callee that only moves it locally.
    : Res h ( ret1 6 )
    ( pass h )

    // Rebound: the old value is dropped at the assignment.
    : ~ Res k ( mkr 7 )
    = k ( mkr 8 )

    // One per iteration.
    : ~ i n 0
    ~ < n 2 { : Res l ( mkr + 10 n ) = n + n 1 }
    ( nurl_println `end` )
    ^ 0
}
