// OPEN in 0.72.0 — a closure defined inside a `% Drop` impl drops the impl's receiver at the end of its own body.
// The impl body ends with the receiver's drop glue, and the non-capturing closure literal inside it gets
// the same epilogue, aimed at the closure's own first slot: each ( f 1 ) reads its integer argument as
// a Note and releases the "String" at address 1. Without the closure the impl runs clean.
// UBSan: runtime error: load of misaligned address 0x000000000001 in nurl_vec_drop (runtime_core.c).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Note { String text ( Vec String ) tags }

% Drop Note { @ drop sink Note h → v {
        : ( @ v i ) f \ i k → v { ( nurl_println ( nurl_str_int k ) ) }
        ( f 1 ) ( f 2 )
    } }

@ main → i {
    : Note n @ Note { ( string_from `n` ) ( vec_new [String] ) }
    ( vec_push [String] . n tags ( string_from `t` ) )
    ( nurl_println `ran` )
    ^ 0
}
