// diag_thread_arc_shared_mutation.nu — two threads mutating the contents of
// one `Arc ( Vec i )`.
//
// docs/MEMORY.md §6.5 listed this as the concrete unchecked data race:
// "`Arc` makes the *refcount* atomic, not your data". It was true, and
// it was reachable from ordinary code — no `*T`, no FFI, no casts:
//
//     : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )
//     : ( @ v ) w1 \ → v { : ( Vec i ) v ( arc_get … a )  ( vec_push … ) }
//
// Measured before the fix, 2 threads × 2000 pushes: 5 of 8 runs
// segfaulted and the survivors returned 2000 / 2996 / 3166 instead of
// 4000. `arc_get` over a manually-managed handle hands back a COPY OF
// THE HANDLE, aliasing the one buffer, so both workers write the same
// length and the same backing pointer — and whichever reallocates first
// frees the buffer the other is still holding.
//
// The error fires at `thread_spawn`, not at the mutation: mutating an
// Arc's contents from ONE thread is ordinary correct code (see
// thread_arc_shared_mutation_ok.nu), so it is the detach that makes it a
// race and the detach that the diagnostic names.

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) d ( vec_new [i] )
    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] d )

    : ( @ v ) w1 \ → v {
        : ( Vec i ) v ( arc_get [( Vec i )] a )
        : ~ i k 0
        ~ < k 2000 { ( vec_push [i] v k ) = k + k 1 }
    }

    : !Thread ThreadErr r1 ( thread_spawn w1 )
    ?? r1 { T t → { ( thread_join t ) } F e → { ( nurl_print `spawn fail\n` ) } }
    ^ 0
}
