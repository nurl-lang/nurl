// destructor_yielding_while_a_panic_drains_it_runs_clean: fibers whose `recover` extents hold `% Drop` values with a destructor that yields around an allocation of its own (and panics, or runs a recover of its own that panics), on one worker and on four; each extent panics.
// Guard for agora #623: a panic's drain kept its depth and its record of what it freed per worker thread. The drain is the fiber's now, exchanged with its journal around every switch, and the drain loop reads no thread-local across a destructor's call.
// main 3d2375c: accepted, UBSan `passing zero to __builtin_clz()` in nurl__jrnl_bucket (a parked drain ended by another fiber's frame left its journal's live count under zero); with four workers a null NurlPanicFrame in nurl_panic and a double free in the drain.
// map: §7.2 | A2 | runs-clean | - | agora #623 guard: a destructor that yields while a panic's drain runs it, the fiber parked mid-drain and resumed on another worker
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/thread.nu`

: Y { String tag i boom }

% Drop Y { @ drop Y y → v {
        ( yield )
        : String scratch ( string_from ( nurl_str_cat `scratch ` ( string_data . y tag ) ) )
        ( yield )
        ? == . y boom 1 { ( panic `panic in a drop` ) } {}
        ? == . y boom 2 {
            : !v PanicInfo q ( recover \ → v {
                : String inner ( string_from `inner value of a drop's own extent` )
                ( yield )
                ( panic `inner panic` )
            } )
        } {}
        ( yield ) } }

: ~ i g_caught 0

@ mk i k i boom → Y { ^ @ Y { ( string_from ( nurl_str_cat `value long enough for the heap ` ( nurl_str_int k ) ) ) boom } }

@ body i k Mutex m → v {
    ? == 0 % k 4 {
        : ~ i j 0
        ~ < j 20 { : String t ( string_from ( nurl_str_cat `churn churn churn churn ` ( nurl_str_int j ) ) ) ( yield ) = j + j 1 }
        ( mutex_lock m ) = g_caught + g_caught 1 ( mutex_unlock m )
    } {
        : !v PanicInfo r ( recover \ → v {
            : Y a ( mk k 2 )
            : Y b ( mk k % k 2 )
            : String s ( string_from `a plain string long enough for a heap block` )
            ( yield )
            ( panic `plain panic` )
        } )
        ?? r { T _ → {} F _ → { ( mutex_lock m ) = g_caught + g_caught 1 ( mutex_unlock m ) } }
    }
}

@ main → i {
    ( runtime_init 1 )
    : Mutex m1 ( mutex_new )
    : ~ i k1 1
    ~ <= k1 40 {
        : i kk1 k1
        : Fiber f1 ( spawn_owned \ → v { ( body kk1 m1 ) } )
        = k1 + k1 1
    }
    ( runtime_run )
    ( runtime_shutdown )
    ( mutex_free m1 )
    ( runtime_init 4 )
    : Mutex m ( mutex_new )
    : ~ i k 1
    ~ <= k 120 {
        : i kk k
        : Fiber f ( spawn_owned \ → v { ( body kk m ) } )
        = k + k 1
    }
    ( runtime_run )
    ( runtime_shutdown )
    ( mutex_free m )
    ( nurl_println ( nurl_str_cat `caught ` ( nurl_str_int g_caught ) ) )
    ^ 0
}
