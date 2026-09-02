// owned_return_in_arms.nu — a helper whose EVERY return is an owned call
// from inside a `?` arm, with no tail return, must still be read as
// returning an owned string, so the caller's `: s` binding is dropped.
//
// The return site used to record the function's ownership flag with a
// plain scope-local define; a `?` arm is its own scope, so the flag died
// with the arm's pop and the function ended unmarked — every caller then
// leaked the result (4 bytes per volatile_load in the compiler, found by
// LSan on the unikernel demos). The flags are function-level facts and
// are written where they live now. This test is the shape that leaked;
// its value is under the sanitizer corpus, where LSan fails the run on
// any leak — the output itself only shows the strings came back right.
//
// Determinism: no clock, no socket, no env. ASan/LSan-clean.

$ `stdlib/core/string.nu`

// Two arms, two `^ ( owned call )`, no tail.
@ strip_star s pt → s {
    : i n ( nurl_str_len pt )
    ? & > n 0 == ( nurl_str_get pt - n 1 ) 42
    { ^ ( nurl_str_slice pt 0 - n 1 ) }
    { ^ ( nurl_str_slice pt 0 n ) }
}

// Three-way: nested arms, still no tail.
@ classify i k → s {
    ? < k 0 { ^ ( nurl_str_cat `neg` `` ) } {
        ? == k 0 { ^ ( nurl_str_cat `zero` `` ) } { ^ ( nurl_str_cat `pos` `` ) }
    }
}

@ use s pt → v {
    : s et ( strip_star pt )
    ( nurl_println et )
}

@ main → i {
    ( use `i32*` )
    ( use `i64` )
    ( use `` )
    : ~ i k -1
    ~ < k 2 {
        : s c ( classify k )
        ( nurl_println c )
        = k + k 1
    }
    ^ 0
}
