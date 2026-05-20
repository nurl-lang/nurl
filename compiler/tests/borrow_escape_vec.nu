// borrow_escape_vec.nu — BORROW.md Phase 3: escape analysis covers
// the ownership-taking helpers (vec_push / vec_insert / vec_set /
// thread_spawn). These four callees take a value that outlives the
// current scope, so a `: ~`-mutable multi-field-struct closure
// captured by pointer escapes when handed to any of them.
//
// Only `thread_spawn` is exercised here because Vec[(@ v)] isn't a
// valid NURL type — generic-arg type lists don't yet accept anonymous
// closure types, so `vec_push [(@ v)] v cb` won't compile. The
// `gen_call` check matches by fname BEFORE mangling, so the same
// warning fires for vec_push/insert/set as for thread_spawn — adding
// type-list support for closures would unlock those test cases.
//
// Two negative controls confirm the warning is stack-reference-only.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: Counter { i n  i max }

// CASE A — thread_spawn of a byref-capturing closure.
@ case_thread_spawn → v {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) bump \ → v {
        = . c n + . c n 1
    }
    : !Thread ThreadErr t ( thread_spawn bump )
    ?? t {
        T th → { : i _r ( thread_join th ) }
        F _ → {}
    }
}

// CONTROL A — by-value closure capture (no `: ~`). The Counter is
// snapshotted into the env; no dangling pointer. No warning expected.
@ control_value_capture → v {
    : Counter c @ Counter { 0 10 }
    : ( @ v ) bump \ → v {
        = . c n + . c n 1
    }
    : !Thread ThreadErr t ( thread_spawn bump )
    ?? t {
        T th → { : i _r ( thread_join th ) }
        F _ → {}
    }
}

// CONTROL B — vec_push of a non-closure int with a `: ~` Counter in
// scope. The escape check is a closure-binding-only path; ordinary
// scalars MUST NOT warn even when passed to vec_push.
@ control_int_push → v {
    : ~ Counter c @ Counter { 0 10 }
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v . c n )
    ( vec_free [i] v )
}

@ main → i {
    ( case_thread_spawn )
    ( control_value_capture )
    ( control_int_push )
    ^ 0
}
