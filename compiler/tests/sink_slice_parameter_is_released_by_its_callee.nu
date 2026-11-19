// AGORA-892: a `sink [T` parameter is its callee's own, released on every way
// out unless it moves on. Before, nobody released it: `( eat ( mk ) )` leaked
// the slice, and a binding handed to a `sink` was refused as "not yet
// supported". Now a fresh temporary and an owned binding both move over (the
// binding is dead afterwards); the callee releases what it keeps, hands it on
// to another `sink`, returns it, or releases it on a panic's unwind. A
// borrowed `[i` parameter handed on to a `sink` makes its function take it
// over too (the existing cascade), so no caller frees what a callee freed.
$ `stdlib/std/panic.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ eat sink [i a → i { ^ . a 1 }
@ pass sink [i a → i { ^ ( eat a ) }
@ keep sink [i a → [i { ^ a }
@ show [i a → i { ^ ( eat a ) }
@ blow sink [i a → i { ? > . a 1 2 { ( panic `boom` ) } {} ^ . a 1 }

@ main → i {
    ( nurl_println_int ( eat ( mk ) ) )
    ( nurl_println_int ( pass ( mk ) ) )
    : [i k ( keep ( mk ) )
    ( nurl_println_int . k 1 )
    : [i t ( mk )
    ( nurl_println_int ( pass t ) )
    : [i u ( mk )
    ( nurl_println_int ( show u ) )
    : !v PanicInfo r ( recover \ → v { ( nurl_println_int ( blow ( mk ) ) ) } )
    : !v PanicInfo r2 ( recover \ → v { : [i w ( mk ) ( nurl_println_int ( blow w ) ) } )
    ( nurl_println `after` )
    ^ 0
}
