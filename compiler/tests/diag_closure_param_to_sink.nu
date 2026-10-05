// diag_closure_param_to_sink.nu — a closure only borrows its parameters
// (docs/MEMORY.md §7.5): its caller keeps what it passed and drops it.
// Handing one to a declared `sink` (here the release itself) would free
// the value twice, so it is rejected with the reason and the fix.
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ v String ) done \ String s → v { ( string_free s ) }
    : String x ( string_from `abc` )
    ( done x )
    ^ 0
}
