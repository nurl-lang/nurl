// wait_unpollable_fd.nu — a wait on a number that names no descriptor
// answers "ready" at once, and costs nothing (agora #133).
//
// The Linux netpoller indexed a table by fd and grew it to fd + 64 entries
// before asking epoll whether the fd existed: `wait_readable` on 300000000
// (a socket handle passed where its fd belonged) took 33 s and 4.7 GB, and
// a pointer-sized value asked for ~20 GB and aborted. Every value is now
// checked first — a closed fd never grows the table, a negative one is no
// longer a pure timer that waits its whole timeout, one past INT_MAX is no
// longer narrowed onto some other fd — and answered as poll(2) answers an
// fd it cannot poll: ready, so the caller's read says what the fd is.
// More than four live fibers, so the spin probe (whose poll(2) answered
// POLLNVAL first) does not hide the wait.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) fds ( vec_new [i] )
    ( vec_push [i] fds 300000000 )
    ( vec_push [i] fds 140000000000000 )
    ( vec_push [i] fds -5 )
    ( runtime_init 1 )
    : ~ i k 0
    ~ < k 8 {
        ( spawn_owned \ → v { ( sleep_ms 100 ) } )
        = k + k 1
    }
    : ~ i rc0 7
    : ~ i rc1 7
    : ~ i rc2 7
    ( spawn \ → v {
        = rc0 ( wait_readable ( vec_at [i] fds 0 ) 5000 )
        = rc1 ( wait_writable ( vec_at [i] fds 1 ) 5000 )
        = rc2 ( wait_readable ( vec_at [i] fds 2 ) 5000 )
    } )
    : i t0 ( monotonic_ns )
    ( runtime_run )
    : i took / - ( monotonic_ns ) t0 1000000
    ( runtime_shutdown )
    ( nurl_print `300000000: ` ) ( nurl_println_int rc0 )
    ( nurl_print `pointer-sized: ` ) ( nurl_println_int rc1 )
    ( nurl_print `negative: ` ) ( nurl_println_int rc2 )
    ( nurl_print `answered before the timeout: ` ) ( nurl_println ? < took 4000 `yes` `no` )
    ^ 0
}
