// recover_fiber_interleave.nu — recover extents of fibers that interleave
// on one worker thread (and migrate between workers).
//
// The recover-frame chain and the panic journal used to be per THREAD. A
// fiber that yielded inside its extent left its frame on the chain and its
// registrations in the journal; another fiber's extent stacked on top, and
// a panic in the first longjmp'd into the SECOND fiber's frame, from the
// wrong stack, after dropping the second fiber's live values — a segfault
// (an HTTP handler panicking while another connection's handler waits on
// the same worker). The state now travels with the fiber.
//
// Part 1 is deterministic: one worker, a parent fiber spawns both
// children, so they run only when it ends and alternate at each yield.
// Part 2 runs many fibers on four workers; each one's own extent must
// catch its own panic and keep its own values, whatever the schedule.

$ `stdlib/core/string.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/thread.nu`

@ panics_while_other_waits → v {
    : !v PanicInfo r ( recover \ → v {
        : String mine ( string_from `A's value` )
        ( nurl_println `A: in extent` ) ( yield ) ( yield )
        ( nurl_println `A: panics` )
        ( nurl_panic ( string_data mine ) )
    } )
    ?? r { T _ → { ( nurl_println `A: completed?` ) } F e → { ( nurl_println ( nurl_str_cat `A: recovered: ` ( string_data . e msg ) ) ) } }
}

@ waits_while_other_panics → v {
    : !v PanicInfo r ( recover \ → v {
        : String mine ( string_from `C's value, still in use` )
        ( nurl_println `C: in extent` ) ( yield ) ( yield ) ( yield )
        ( nurl_println ( nurl_str_cat `C: ` ( string_data mine ) ) )
    } )
    ?? r { T _ → { ( nurl_println `C: completed` ) } F _ → { ( nurl_println `C: panicked?` ) } }
}

// The same, the other way round, with an extent nested in the waiter.
@ nested_waiter → v {
    : !v PanicInfo outer ( recover \ → v {
        : String a ( string_from `outer value` )
        : !v PanicInfo inner ( recover \ → v {
            : String b ( string_from `inner value` )
            ( nurl_println `D: in inner extent` ) ( yield ) ( yield ) ( yield )
            ( nurl_println ( nurl_str_cat `D: ` ( string_data b ) ) )
        } )
        ( nurl_println ( nurl_str_cat `D: ` ( string_data a ) ) )
    } )
    ( nurl_println `D: done` )
}

@ panics_later → v {
    : !v PanicInfo r ( recover \ → v {
        : String mine ( string_from `E's value` )
        ( nurl_println `E: in extent` ) ( yield )
        ( nurl_println `E: panics` )
        ( nurl_panic ( string_data mine ) )
    } )
    ?? r { T _ → {} F _ → { ( nurl_println `E: recovered` ) } }
}

: ~ i g_caught 0
: ~ i g_kept 0

@ busy_fiber i k Mutex m → v {
    : !v PanicInfo r ( recover \ → v {
        : String mine ( string_from ( nurl_str_int k ) )
        ( yield ) ( yield )
        ? == 0 % k 3 { ( nurl_panic `every third` ) } {}
        ( yield )
        ? == ( nurl_str_to_int ( string_data mine ) ) k {
            ( mutex_lock m ) = g_kept + g_kept 1 ( mutex_unlock m )
        } {}
    } )
    ?? r { T _ → {} F _ → { ( mutex_lock m ) = g_caught + g_caught 1 ( mutex_unlock m ) } }
}

@ main → i {
    ( runtime_init 1 )
    : Fiber p ( spawn_owned \ → v {
        : Fiber a ( spawn_owned \ → v { ( panics_while_other_waits ) } )
        : Fiber c ( spawn_owned \ → v { ( waits_while_other_panics ) } )
    } )
    ( runtime_run )
    : Fiber q ( spawn_owned \ → v {
        : Fiber d ( spawn_owned \ → v { ( nested_waiter ) } )
        : Fiber e ( spawn_owned \ → v { ( panics_later ) } )
    } )
    ( runtime_run )
    ( runtime_shutdown )

    ( runtime_init 4 )
    : Mutex m ( mutex_new )
    : ~ i k 1
    ~ <= k 300 {
        : i kk k
        : Fiber f ( spawn_owned \ → v { ( busy_fiber kk m ) } )
        = k + k 1
    }
    ( runtime_run )
    ( runtime_shutdown )
    ( mutex_free m )
    ( nurl_println ( nurl_str_cat4 `many: caught ` ( nurl_str_int g_caught ) ` kept ` ( nurl_str_int g_kept ) ) )
    ^ 0
}
