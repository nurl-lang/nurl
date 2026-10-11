// H182: a struct literal that leaves a closure field out zero-initialises it: calling the closure jumped to address 0.
// Closed: as h180 — a closure's zero has no code to call, so the field must be given outside `unsafe`.
// ASan: SEGV (main), the call through the zero closure.
$ `stdlib/core/string.nu`

: Hook { i n ( @ i i ) f }

@ main → i {
    : Hook h @ Hook { 5 }
    : ( @ i i ) g . h f
    ( nurl_println_int ( g 3 ) )
    ^ 0
}
