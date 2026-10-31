// thread_consumes_one_capture_frees_shared_atomic: agora #247 — a thread closure consuming one capture freed the spawner's Atomic at thread end: the spawner read it after the join (thread_consumes_one_capture_frees_shared_atomic).
// Closed: a closure whose body releases one capture moves only that one into its env (g_env_released), with what a spawn takes over (g_env_moved); a handle the frame still uses stays a view, which the spawn's adopt shares or copies (gen_env_vtable, gen_env_allocation; agora #247).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §6.5 | A3 | runs-clean | - | agora #247: a thread closure consuming one capture freed the spawner's Atomic at thread end: the spawner read it after the join
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`

@ consume sink String s → i { ^ ( string_len s ) }

@ main → i {
    : Atomic rc_out ( atomic_new -1 )
    : String owned ( string_from `hello` )
    : !Thread ThreadErr srv ( thread_spawn \ → v {
        : i r ( consume owned )
        ( atomic_store rc_out r )
    } )
    ?? srv { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_print_int ( atomic_load rc_out ) )
    ^ 0
}
