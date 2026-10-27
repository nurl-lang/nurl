// OPEN in v0.79.1 — the same class as binding_viewing_a_call_temporary_leaks_it.nu, through a closure: `( mk ( string_from … ) )` with `mk` returning a closure that captures its String parameter without taking it over. The closure's env views the temporary, which nothing drops. LSan (use_stacks=0): the String and its buffer leak (agora #138).
$ `stdlib/core/string.nu`

@ mk String s → ( @ v ) { ^ \ → v { ( nurl_println ( string_data s ) ) } }

@ main → i {
    : ( @ v ) g ( mk ( string_from `x` ) )
    ( g )
    ^ 0
}
