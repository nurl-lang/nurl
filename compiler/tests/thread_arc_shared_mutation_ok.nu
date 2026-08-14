// thread_arc_shared_mutation_ok.nu — the four shapes the shared-mutation
// check must NOT reject. It is the control for
// thread_arc_shared_mutation{,_helper}.nu, and the more important half:
// a diagnostic that also forbids the cure it recommends is worse than no
// diagnostic at all.
//
// 1. Mutating an Arc's contents on ONE thread. There is no second writer,
//    and this is the normal single-threaded use of Arc.
// 2. A thread closure that only READS the contents. Concurrent readers of
//    an unwritten buffer do not race (compiler/tests/arc_threads.nu is
//    built on exactly this).
// 3. A thread closure mutating a Vec it created ITSELF — per-thread
//    state that is never shared, whatever its type.
// 4. THE CURE: mutation under a lock the worker takes itself. This is
//    what the error message tells the writer to do, so it is pinned
//    here; measured at 4000/4000 over ten runs where the unguarded
//    version segfaulted five times in eight.
//
// Note 4 works because the lock depth is reset when a closure body is
// entered — a lock held by the DEFINING thread says nothing about the
// thread the closure is detached onto, so the body has to take it.
//
// Spawns real pthreads, so it carries the same declaration as
// thread_basic / arc_threads.
// requires: live

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    // 1 — single-threaded mutation through an Arc.
    : ( Vec i ) d1 ( vec_new [i] )
    : ( Arc ( Vec i ) ) a1 ( arc_new [( Vec i )] d1 )
    : ( Vec i ) v1 ( arc_get [( Vec i )] a1 )
    ( vec_push [i] v1 7 )
    ( nurl_print ( nurl_str_int ( vec_len [i] v1 ) ) )
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

    // 4 — the cure: mutate the shared contents while holding the lock.
    : Mutex m ( mutex_new )
    : ( @ v ) guarded \ → v {
        ( mutex_lock m )
        : ( Vec i ) v ( arc_get [( Vec i )] a1 )
        ( vec_push [i] v 2 )
        ( mutex_unlock m )
    }
    : !Thread ThreadErr r3 ( thread_spawn guarded )
    ?? r3 { T t → { ( thread_join t ) } F e → { ( nurl_print `spawn fail\n` ) } }

    ( mutex_free m )
    ^ 0
}
