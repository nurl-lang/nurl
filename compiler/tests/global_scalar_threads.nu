// Scalar mutable globals reached from several threads: a flag, a counter,
// a float and a string view. Each is read and written with relaxed atomics
// (global_atomic_ir.sh checks the IR), so the race between the writer and
// the reader is defined: the reader sees whole values only, and one
// location's values in the order they were written.
//
// The reader samples a fixed number of times rather than waiting for the
// writer: where threads are coroutines (the unikernel and nolibc targets)
// the writer runs only once the reader blocks in the join, and a loop
// spinning on its progress would never end there.
$ `stdlib/core/io.nu`
$ `stdlib/std/thread.nu`

: ~ b g_done F
: ~ i g_count 0
: ~ f g_level 0.0
: ~ u g_byte 0
: ~ s g_name `start`

@ main → i {
    : ( @ v ) body \ → v {
        : ~ i k 0
        ~ < k 1000 {
            = g_count + k 1
            = g_level # f k
            = g_byte # u & k 255
            = k + k 1
        }
        = g_name `done`
        = g_done T
    }
    ?? ( thread_spawn_owned body ) {
        T t → {
            : ~ i last 0
            : ~ i bad 0
            : ~ i r 0
            ~ < r 100000 {
                : i c g_count
                ? | < c last > c 1000 { = bad + bad 1 } {}
                = last c
                = r + r 1
            }
            : i _j ( thread_join t )
            ? == bad 0 { ( nurl_println `reads whole and in order` ) } { ( nurl_println `a torn or reordered read` ) }
        }
        F _ → {}
    }
    ? g_done { ( nurl_println `done flag seen` ) } { ( nurl_println `no flag` ) }
    ( nurl_println_int g_count )
    ( nurl_println_int # i g_level )
    ( nurl_println_int # i g_byte )
    ( nurl_println g_name )
    ^ 0
}
