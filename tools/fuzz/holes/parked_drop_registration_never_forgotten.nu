// parked_drop_registration_never_forgotten: h291 made the panic journal register a value whose journal thunk is emitted only at module end (a struct holding a lock guard, dropped by a drop the compiler writes) — but the forget that ends the registration when the value is dropped normally still waited for the thunk to exist, and never came: the registration outlived the function. A panic later in the same recover extent then dropped the value again, from a frame that had returned (stack-use-after-return; a guard unlocked twice).
// Closed: the forget goes ahead whenever the push did (thunk out, or parked: `ujdrop##`).
// main (before this PR): AddressSanitizer reported stack-use-after-return in __jdrop_Held, called by the panic's journal drain.
// map: §7.2 | A2 | runs-clean | h294 | a value whose journal thunk is parked for module end was registered but never forgotten: a later panic dropped it from a returned frame
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/panic.nu`

: Fr { i v }

: Held {
    ( WGuard Fr ) g
    i n
}

@ peek ( RwLocked Fr ) l → i {
    : Held h @ Held { ( rw_write [Fr] l ) 1 }
    ^ . h n
}

@ main → i {
    : ( RwLocked Fr ) l ( rw_new [Fr] @ Fr { 0 } )
    : ~ i got 0
    : !v PanicInfo r ( recover \ → v {
        = got ( peek l )
        ( panic `after peek returned` )
    } )
    ?? r { T _ → {} F p → { ( panic_info_free p ) } }
    : ( WGuard Fr ) g ( rw_write [Fr] l )
    ( nurl_print `peeked ` ) ( nurl_println_int got )
    ^ 0
}
