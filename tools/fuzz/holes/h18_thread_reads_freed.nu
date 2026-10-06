// H18: a thread reads a String the spawning thread frees.
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
