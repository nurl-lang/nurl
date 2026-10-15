// closure_inout.nu — closures that take a parameter `inout`.
//
// `( @ R inout T )` / `\ inout T x → R { … }`: the closure gets the
// caller's binding by address, as an `inout` function parameter does, so
// it changes the caller's value in place — scalars included — and the
// value never moves. locked_update / locked_apply use it to run code on a
// Locked value where it lives, with no copy out and back.
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

: P { i n ( Vec i ) v }

@ app_twice ( @ v inout P ) f inout P p → v { ( f p ) ( f p ) }

@ main → i {
    : ~ P q @ P { 0 ( vec_new [i] ) }
    : ( @ v inout P ) g \ inout P p → v { = . p n + . p n 1 ( vec_push [i] . p v . p n ) }
    ( g q )
    ( app_twice g q )
    ( nurl_println ( nurl_str_int . q n ) )
    ( nurl_println ( nurl_str_int ( vec_len [i] . q v ) ) )
    // In place under a lock.
    : ( Locked P ) lk ( locked_new [P] @ P { 10 ( vec_new [i] ) } )
    : ~ i k 0
    ~ < k 4 {
        : i kk k
        ( locked_update [P] lk \ inout P e → v { = . e n + . e n 1 ( vec_push [i] . e v kk ) } )
        = k + k 1
    }
    : i total ( locked_apply [P i] lk \ inout P e → i { ^ + . e n ( vec_len [i] . e v ) } )
    ( nurl_println ( nurl_str_int total ) )
    ^ 0
}
