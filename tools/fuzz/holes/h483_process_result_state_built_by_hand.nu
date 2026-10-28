// H483: a `__CProcResult` literal of the program's own handed 4096 to
// nurl_proc_free when it was dropped (and ProcChildImpl's drop frees the
// runtime child record its `craw` names on Windows).
// Closed: both are sealed (`raw :`).
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/std/process.nu`

@ main → i {
    : __CProcResult c @ __CProcResult { 4096 }
    ( nurl_println_int . c res )
    ^ 0
}
