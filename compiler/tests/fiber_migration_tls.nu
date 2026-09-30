// fiber_migration_tls.nu — fibers that allocate, free and yield on four
// workers, inside and outside recover extents, with a panic in every
// seventh. A fiber can resume on another worker thread than it yielded
// on; the runtime's thread-locals (the panic journal, the return-ownership
// channel) must then be the new thread's. Before the runtime kept those
// accesses out of line (or in single-instruction asm), LTO inlined them
// into `churn` with the thread pointer loaded once at entry and reused
// after every yield: the fiber wrote another thread's journal, and a
// panic drain freed a Vec twice (a segfault in ~1 run of 5 under load).
// Prints the same sum and zero live allocations on every schedule.
// Windows has no fiber backend yet (spawn is a stub, docs/ASYNC.md):
// outputs-windows/ pins what the stubs print, as for async_basic.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/thread.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

: ~ i g_sum 0

@ churn i k → i {
    : ~ i acc 0
    : ~ i j 0
    ~ < j 200 {
        : String s ( string_from `abcdefghijklmnopqrstuvwxyz` )
        ( yield )
        ( string_push_str s ( nurl_str_int j ) )
        : ( Vec i ) v ( vec_new [i] )
        ( vec_push [i] v j ) ( yield ) ( vec_push [i] v k )
        = acc + acc + ( string_len s ) ( vec_len [i] v )
        = j + j 1
    }
    ^ acc
}

@ worker_body i k Mutex m → v {
    : !v PanicInfo r ( recover \ → v {
        : i a ( churn k )
        ( mutex_lock m ) = g_sum + g_sum a ( mutex_unlock m )
        ? == 0 % k 7 { ( nurl_panic `seventh` ) } {}
    } )
    : i b ( churn + k 1 )
    ( mutex_lock m ) = g_sum + g_sum b ( mutex_unlock m )
}

@ main → i {
    : i l0 - ( nurl_alloc_count ) ( nurl_free_count )
    ( runtime_init 4 )
    : Mutex m ( mutex_new )
    : ~ i k 1
    ~ <= k 200 { : i kk k : Fiber f ( spawn_owned \ → v { ( worker_body kk m ) } ) = k + k 1 }
    ( runtime_run )
    ( runtime_shutdown )
    ( mutex_free m )
    : i l1 - ( nurl_alloc_count ) ( nurl_free_count )
    ( nurl_println ( nurl_str_cat4 `sum ` ( nurl_str_int g_sum ) ` live ` ( nurl_str_int - l1 l0 ) ) )
    ^ 0
}
