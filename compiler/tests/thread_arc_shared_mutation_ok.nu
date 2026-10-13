// thread_arc_shared_mutation_ok.nu — the shapes the shared-mutation check
// must NOT reject. It is the control for diag_thread_arc_shared_mutation
// {,_helper}.nu and diag_thread_arc_payload_through_call.nu, and the more
// important half: a diagnostic that also forbids the cure it recommends
// is worse than no diagnostic at all.
//
// An Arc's payload is frozen once made (docs/MEMORY.md §6.5): every
// thread holding a clone reads it without a lock, so no thread may change
// it — not the one that made it, and not one holding some Mutex, since no
// type ties that lock to the data. What stays legal, and is pinned here:
//
// 1. Building the value first, then sharing it: arc_new takes it whole.
// 2. A thread closure that only READS the contents. Concurrent readers of
//    an unwritten buffer do not race (compiler/tests/arc_threads.nu is
//    built on exactly this).
// 3. A thread closure mutating a Vec it created ITSELF — per-thread
//    state that is never shared, whatever its type.
// 4. THE CURE: state threads share and change is a Locked, changed only
//    inside locked_with, which holds the Locked's own lock for the call.
//
// Spawns real pthreads, so it carries the same declaration as
// thread_basic / arc_threads.
// requires: live

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    // 1 — build, then share.
    : ( Vec i ) d1 ( vec_new [i] )
    ( vec_push [i] d1 7 )
    : ( Arc ( Vec i ) ) a1 ( arc_new [( Vec i )] d1 )
    ( nurl_print ( nurl_str_int ( vec_len [i] ( arc_get [( Vec i )] a1 ) ) ) )
    ( nurl_print `\n` )

    // 2 — a worker that only reads.
    : ( @ v ) reader \ → v {
        : ( Vec i ) v ( arc_get [( Vec i )] a1 )
        ( nurl_print ( nurl_str_int ( vec_len [i] v ) ) )
        ( nurl_print `\n` )
    }
    : !Thread ThreadErr r1 ( thread_spawn reader )
    ?? r1 { T t → { ( thread_join t ) } F e → { ( nurl_print `spawn fail\n` ) } }

    // 3 — a worker mutating only its own Vec.
    : ( @ v ) local_only \ → v {
        : ( Vec i ) mine ( vec_new [i] )
        ( vec_push [i] mine 1 )
        ( vec_free [i] mine )
    }
    : !Thread ThreadErr r2 ( thread_spawn local_only )
    ?? r2 { T t → { ( thread_join t ) } F e → { ( nurl_print `spawn fail\n` ) } }

    // 4 — the cure: shared state in a Locked, changed under its own lock.
    : ( Locked ( Vec i ) ) shared ( locked_new [( Vec i )] ( vec_new [i] ) )
    : ( @ v ) guarded \ → v {
        ( locked_with [( Vec i )] shared \ ( Vec i ) v → v { ( vec_push [i] v 2 ) } )
    }
    : !Thread ThreadErr r3 ( thread_spawn guarded )
    ?? r3 { T t → { ( thread_join t ) } F e → { ( nurl_print `spawn fail\n` ) } }
    ? != 1 ( vec_len [i] ( locked_get [( Vec i )] shared ) ) { ( nurl_print `lost\n` ) } {}
    ^ 0
}
