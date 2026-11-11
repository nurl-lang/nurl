// arm_ending_in_a_lend_of_an_outer_binding_releases_its_locals: `: S e ? c { : String junk … ( vec_at [S] v 0 ) } ( vec_at [S] v 1 )`, `v` bound above the arm; the same in a `??` arm and as a call argument.
// Closed: an arm whose value is a call's lend out of bindings made outside the arm releases its locals at its exit (mem_arm_outer_lend: the gate of the arm's parked drops is "the callee lends from none of the arguments that are the arm's own or no plain binding"). Parked as "the value may be one of them", `junk` was released by nobody once the value was consumed (agora #595).
// main b82c116: accepted; LeakSanitizer: the arm's String, once per run of the arm.
// map: §7.1 | A2 | runs-clean | - | agora #595: a `?` / `??` arm holding an owned local and ending in a lend of an outer binding leaks the local
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S {
    String name
    i n
}

: | E {
    A i
    B
}

@ cond i c → i {
    : ~ ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    ( vec_push [S] v @ S { ( string_from `another element string long enough for a heap buffer` ) 2 } )
    : S e ? > c 1 { : String junk ( string_from `a junk string long enough for a heap buffer here` ) ( vec_at [S] v 0 ) } ( vec_at [S] v 1 )
    ^ . e n
}

@ match E x → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : String e ?? x { A k → { : String junk ( string_from `a junk string long enough for a heap buffer here` ) ( vec_at [String] v 0 ) } B → ( string_from `the other arm's own string, long enough` ) }
    ^ ( string_len e )
}

@ arg i c → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    ^ ( string_len ? > c 0 { : String junk ( string_from `a junk string long enough for a heap buffer here` ) ( vec_at [String] v 0 ) } ( vec_at [String] v 0 ) )
}

// The arm's own Vec lends the value: copied there, as before (agora #191).
@ local i c → i {
    : ~ ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : S e ? > c 1 { : ~ ( Vec S ) u ( vec_new [S] ) ( vec_push [S] u @ S { ( string_from `an arm-local element, long enough for the heap` ) 7 } ) : String junk ( string_from `a junk string long enough for a heap buffer here` ) ( vec_at [S] u 0 ) } ( vec_at [S] v 0 )
    ^ + . e n ( string_len . e name )
}

@ main → i {
    ( nurl_println_int ( cond 2 ) )
    ( nurl_println_int ( cond 0 ) )
    ( nurl_println_int ( match @ E { A 1 } ) )
    ( nurl_println_int ( match @ E { B } ) )
    ( nurl_println_int ( arg 1 ) )
    ( nurl_println_int ( local 2 ) )
    ( nurl_println_int ( local 0 ) )
    ^ 0
}
