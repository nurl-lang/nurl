// thread_consumes_one_capture_frees_shared_arc: agora #247 — the same with an `( Arc i )` the spawner reads after the join (thread_consumes_one_capture_frees_shared_arc).
// Closed: a closure whose body releases one capture moves only that one into its env (g_env_released), with what a spawn takes over (g_env_moved); a handle the frame still uses stays a view, which the spawn's adopt shares or copies (gen_env_vtable, gen_env_allocation; agora #247).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §6.5 | A3 | runs-clean | - | agora #247: the same with an `( Arc i )` the spawner reads after the join
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`

@ consume sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ( Arc i ) a ( arc_new [i] 41 )
    : String owned ( string_from `hello` )
    : !Thread ThreadErr srv ( thread_spawn \ → v {
        : i r ( consume owned )
        ( nurl_print_int + r ( arc_get [i] a ) )
    } )
    ?? srv { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_print_int ( arc_get [i] a ) )
    ^ 0
}
