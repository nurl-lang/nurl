// own_struct_named_rc_of_numbers_captured_by_a_thread_runs_clean: a program's own `: Rc { i a i b }`, two numbers, captured by a thread
// Closed: agora #714 (precision), the Send walk asks what the type is; a program's own `Rc` is whatever its fields make it.
// main ffce8adb: refused ("it reaches an 'Rc', whose refcount is NOT atomic").
// map: §6.5 | A3 | runs-clean | - | agora #714: a program's own struct named Rc holding numbers is Send by its fields
$ `stdlib/std/thread.nu`

: Rc { i a i b }

@ main → i {
    : Rc r @ Rc { 3 4 }
    : ( @ v ) body \ → v { ( nurl_println_int + . r a . r b ) }
    ?? ( thread_spawn body ) { T th → { : i j ( thread_join th ) } F e → {} }
    ^ 0
}
