// view_param_captured_by_a_spawned_thread: a closure capturing a view parameter is handed to thread_spawn and the thread returned; the caller frees its String before the thread reads.
// Closed: a view parameter stands for itself as a source in its function's walk (`pv_`, bck_sx_name), so the rules for a view of a local apply to it: a string global may not be given one (bck_global_view_check), and what runs on another thread may not hold one (Family 2, agora #422).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §6.5 | A3 | rejected | - | a view parameter captured by a spawned thread that outlives the caller's String
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ start s msg → !Thread ThreadErr {
    : ( @ v ) job \ → v {
        ( sleep_ms 50 )
        ( nurl_print msg ) ( nurl_print `\n` )
    }
    ^ ( thread_spawn job )
}

@ main → i {
    : String m ( string_from `a message on the heap, long enough to matter` )
    : !Thread ThreadErr t ( start ( string_data m ) )
    ( string_free m )
    : i _j ?? t { T th → ( thread_join th ) F _ → 0 }
    ^ 0
}
