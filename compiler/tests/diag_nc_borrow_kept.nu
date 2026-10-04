// A borrowed value that cannot be copied — here a parameter's Database
// field — handed to a callee that keeps it (vec_push's element). The Vec
// would own what the Holder still owns, and both would close it: it was
// moved in silently and the second drop was a use-after-free. The owner
// has to give it up instead (a 'sink' parameter, or the owner itself).
$ `stdlib/core/vec.nu`
$ `stdlib/ext/sqlite.nu`

: Holder {
    Database db
}

@ keep Holder h ( Vec Database ) out → v {
    ( vec_push [Database] out . h db )
}

@ main → i {
    ^ 0
}
