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
// On Windows the panic's longjmp unwinds through the CRT, which checks
// every frame against the TIB stack bounds — the Win64 switch carries
// them per fiber (runtime_ctx.c), which is what this part also covers.
//
// Part 3 (agora #623): a panic's drain runs destructors that yield. The
// fiber waits mid-drain while others run on its worker (and, with four
// workers, comes back on another one). The drain's depth and its record
// of what it freed were per thread: the fibers that ran next took the
// parked drain for their own and ended it (UBSan: clz(0) in the journal),
// and a fiber resumed elsewhere found no drain there (a double free, a
// null panic frame). A drain is the fiber's now, like its journal.

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

// Part 3's value: its destructor yields around an allocation of its own,
// and panics (boom 1) or runs a recover of its own that panics (boom 2).
: Y { String tag i boom i loud }

% Drop Y { @ drop Y y → v {
        ( yield )
        : String scratch ( string_from ( nurl_str_cat `drops ` ( string_data . y tag ) ) )
        ( yield )
        ? == . y loud 1 { ( nurl_println ( string_data scratch ) ) } {}
        ? == . y boom 1 { ( panic `panic in a drop` ) } {}
        ? == . y boom 2 {
            : !v PanicInfo q ( recover \ → v {
                : String inner ( string_from `a drop's own extent` )
                ( yield )
                ( panic `inner panic` )
            } )
        } {}
        ( yield ) } }

@ mk_y s tag i boom i loud → Y { ^ @ Y { ( string_from tag ) boom loud } }

@ drains_while_other_waits → v {
    : !v PanicInfo r ( recover \ → v {
        : Y a ( mk_y `F's first value` 2 1 )
        : Y b ( mk_y `F's second value` 1 1 )
        ( nurl_println `F: in extent` ) ( yield )
        ( nurl_println `F: panics` )
        ( nurl_panic `F's cause` )
    } )
    ?? r { T _ → { ( nurl_println `F: completed?` ) } F e → { ( nurl_println ( nurl_str_cat `F: recovered: ` ( string_data . e msg ) ) ) } }
}

@ waits_while_other_drains → v {
    : !v PanicInfo r ( recover \ → v {
        : String mine ( string_from `G's value, still in use` )
        ( nurl_println `G: in extent` )
        : ~ i j 0
        ~ < j 8 { : String t ( string_from `G's churn, freed while F drains` ) ( yield ) = j + j 1 }
        ( nurl_println ( nurl_str_cat `G: ` ( string_data mine ) ) )
    } )
    ?? r { T _ → { ( nurl_println `G: completed` ) } F _ → { ( nurl_println `G: panicked?` ) } }
}

: ~ i g_drained 0

@ drain_fiber i k Mutex m → v {
    : !v PanicInfo r ( recover \ → v {
        : Y a ( mk_y ( nurl_str_cat `first value of ` ( nurl_str_int k ) ) % k 3 0 )
        : Y b ( mk_y ( nurl_str_cat `second value of ` ( nurl_str_int k ) ) 0 0 )
        ( yield )
        ( nurl_panic `drain under migration` )
    } )
    ?? r { T _ → {} F _ → { ( mutex_lock m ) = g_drained + g_drained 1 ( mutex_unlock m ) } }
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

    ( runtime_init 1 )
    : Fiber pd ( spawn_owned \ → v {
        : Fiber fd ( spawn_owned \ → v { ( drains_while_other_waits ) } )
        : Fiber gd ( spawn_owned \ → v { ( waits_while_other_drains ) } )
    } )
    ( runtime_run )
    ( runtime_shutdown )

    ( runtime_init 4 )
    : Mutex md ( mutex_new )
    : ~ i kd 1
    ~ <= kd 200 {
        : i kk kd
        : Fiber f ( spawn_owned \ → v { ( drain_fiber kk md ) } )
        = kd + kd 1
    }
    ( runtime_run )
    ( runtime_shutdown )
    ( mutex_free md )
    ( nurl_println ( nurl_str_cat `drains: caught ` ( nurl_str_int g_drained ) ) )
    ^ 0
}
