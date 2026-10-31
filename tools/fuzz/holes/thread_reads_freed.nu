// thread_reads_freed: a thread reads a String the spawning thread frees.
// map: §6.5 | A3 | rejected | h18 | spawned thread reads a String the spawning thread frees; A3.0: the String moves to the thread, so the spawner cannot free it
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ main → i {
    : String t ( string_from `shared between threads, long heap string` )
    : !Thread ThreadErr th ( thread_spawn \ → v { ( sleep_ms 50 ) ( nurl_println ( string_data t ) ) } )
    ( string_free t )
    ?? th { T x → { : i _j ( thread_join x ) } F _ → {} }
    ^ 0
}
