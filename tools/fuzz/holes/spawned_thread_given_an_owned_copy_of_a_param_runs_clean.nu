// spawned_thread_given_an_owned_copy_of_a_param_runs_clean: the form tools/fuzz/parse_harness.nu and nurl-mcp's HTTP handler take now — the closure handed to another thread captures a String of its own made from the view parameter, so the caller's String may go first (view_param_captured_by_a_spawned_thread).
// main 4f15689: accepted; ran clean.
// map: §6.5 | A3 | runs-clean | - | a spawned thread given an owned copy of a view parameter
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ start s msg → !Thread ThreadErr {
    : String own ( string_from msg )
    : ( @ v ) job \ → v {
        ( sleep_ms 50 )
        ( nurl_print ( string_data own ) ) ( nurl_print `\n` )
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
