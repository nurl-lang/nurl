// tests/progs/threadprobe.nu — real threads over one shared heap.
//
// Four threads, each building and dropping vectors big enough to push
// the guest heap past its first arena (so memory.grow happens on a
// spawned thread and every other thread has to see the new bound), then
// folding their count into a shared cell under a mutex. Built twice by
// tests/threads_test.sh — native and wasm32-wasi with --threads — and
// the two runs must print the same thing.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : Mutex m ( mutex_new )
    : *i total ( nurl_alloc 8 )
    ( nurl_poke # s total 0 0 )
    : ( @ v ) body \ → v {
        : ~ i sum 0
        : ~ i r 0
        ~ < r 8 {
            : ( Vec i ) v ( vec_new [i] )
            : ~ i k 0
            ~ < k 20000 { ( vec_push [i] v k ) = sum + sum 1 = k + k 1 }
            ( vec_free [i] v )
            = r + r 1
        }
        ( mutex_lock m )
        ( nurl_poke # s total 0 + ( nurl_peek # s total 0 ) sum )
        ( mutex_unlock m )
    }
    : ( Vec s ) ths ( vec_new [s] )
    : ~ i i 0
    ~ < i 4 {
        ?? ( thread_spawn body ) {
            T t → { ( vec_push [s] ths . t raw ) }
            F e → { ( nurl_print `spawn failed: ` ) ( nurl_println ( thread_err_name e ) ) }
        }
        = i + i 1
    }
    : i n ( vec_len [s] ths )
    : ~ i j 0
    ~ < j n { ?? ( vec_get [s] ths j ) { T r → ( thread_join @ Thread { r } ) F → {} } = j + j 1 }
    ( nurl_print `threads: ` ) ( nurl_println ( nurl_str_int n ) )
    ( nurl_print `total: ` ) ( nurl_println ( nurl_str_int ( nurl_peek # s total 0 ) ) )
    ( vec_free [s] ths ) ( nurl_free # s total ) ( mutex_free m )
    ^ 0
}
