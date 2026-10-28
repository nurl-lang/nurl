// H379: a closure a call hands back over its temporary argument (`( mk ( string_from … ) )`, `mk` capturing its String parameter without taking it over) leaked the temporary: the env views it, and nothing consumed the closure before the binding took it.
// Closed: as h378 — the call's result may view the temporary and no call consumes it (resolve_view_temps, agora #138).
// v0.79.1: accepted; LeakSanitizer reported the String and its buffer.
$ `stdlib/core/string.nu`

@ mk String s → ( @ v ) { ^ \ → v { ( nurl_println ( string_data s ) ) } }

@ main → i {
    : ( @ v ) g ( mk ( string_from `x` ) )
    ( g )
    ^ 0
}
