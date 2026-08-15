// diag_send_enum_payload.nu
// An enum's LLVM body is `{ i64, i64, … }` — every payload slot is
// bit-complete and type-free (spec §4.7) — so a field walk cannot see
// what a variant carries. The declared payload types are the only
// place this Rc is still visible, and the walk has to look there.

$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`

: | Wrap { Held ( Rc i ) Empty }

@ main → i {
    : ( Rc i ) shared ( rc_new [i] 0 )
    : Wrap w @ Wrap { Held shared }
    : ( @ v ) work \ → v { : Wrap c w }
    : !Thread ThreadErr r ( thread_spawn work )
    ^ 0
}
