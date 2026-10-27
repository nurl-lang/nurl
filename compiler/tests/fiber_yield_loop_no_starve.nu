// fiber_yield_loop_no_starve.nu — a fiber that yields in a loop must not
// starve the netpoller or the global queue on its worker.
//
// On ONE worker, a spinner yields until a flag is set; a sleeper parks
// on a 20 ms timer and sets the flag when it wakes. A yield re-queues
// the spinner on the worker's local queue, so the local queue never
// empties — and the scheduler used to look at the netpoller (timers,
// I/O) and the global queue (unparked fibers) only once it did. The
// sleeper's timer could never fire and this program never ended. The
// worker now polls the netpoller every 16th dispatch regardless, and
// serves its local and the global queue oldest first, so a yield (which
// re-stamps the spinner) never goes ahead of a fiber already waiting.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/time.nu`

: ~ i stop 0
: ~ i spins 0

@ main → i {
    ( runtime_init 1 )
    : ( @ v ) spinner \ → v {
        ~ == stop 0 {
            = spins + spins 1
            ( yield )
        }
    }
    : ( @ v ) sleeper \ → v {
        ( sleep_ms 20 )
        = stop 1
    }
    ( spawn spinner )
    ( spawn sleeper )
    ( runtime_run )
    ( runtime_shutdown )
    ( nurl_print `sleeper_woke=yes\n` )
    ( nurl_print `spinner_ran=` )
    ( nurl_print ? > spins 0 `yes` `no` )
    ( nurl_print `\n` )
    ^ 0
}
