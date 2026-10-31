// thread_captures_owned_string: a thread closure captures an owned string that the spawning function releases on return.
// map: §6.5 | A3 | rejected | h92 | thread closure captures string the spawning function frees on return
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ spawn_it → !Thread ThreadErr {
    : s msg ( nurl_str_cat `a fresh heap string ` `for the worker thread to print` )
    ^ ( thread_spawn \ → v { ( sleep_ms 50 ) ( nurl_println msg ) } )
}

@ main → i {
    : !Thread ThreadErr t ( spawn_it )
    ?? t { T h → { ( thread_join h ) } F e → {} }
    ^ 0
}
