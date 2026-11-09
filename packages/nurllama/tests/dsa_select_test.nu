// nurllama/tests/dsa_select_test.nu — lk_dsa_select keeps exactly the keys
// the counting rule keeps (agora #522).
//
// The rule: key t of position b is in when fewer than topk keys beat it — a
// higher score, or an equal one at a lower index. The kernel finds the same
// set by quickselect in linear time. Here random scores, from widely spread
// to a handful of distinct values (ties everywhere), at npos below, at and
// above topk, and several positions at once, are run through the kernel on
// whatever backend the run uses (NURL_GPU=cpu for the host one), and every
// row is held against the rule computed here. Then the time per launch at
// npos 4k..32k, topk 2048.
//
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/dsa_select_test.nu /tmp/ds && NURL_GPU=cpu /tmp/ds

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/time.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `src/kernels.nu`

: ~ i g_seed 88172645463325252

@ rnd i m → i {
    = g_seed & + * g_seed 6364136223846793005 1442695040888963407 9223372036854775807
    ^ % >> g_seed 17 m
}

// The rule itself: fewer than topk of the row's npos keys beat key t.
@ rule_keeps ( Vec f32 ) sc i row i npos i t i topk → b {
    : f32 st ( vec_at [f32] sc + row t )
    : ~ i beat 0
    : ~ i u 0
    ~ < u npos {
        : f32 su ( vec_at [f32] sc + row u )
        ? | > su st & == su st < u t { = beat + beat 1 } {}
        = u + u 1
    }
    ^ < beat topk
}

// One case: `batch` positions, the first with npos0 keys, `distinct` score
// values. F when a row differs from the rule (it says which).
@ one GpuKit kit i npos0 i batch i maxpos i topk i distinct → b {
    : ( Vec u ) raw ( vec_new [u] )
    : ( Vec f32 ) sc ( vec_new [f32] )
    : ~ i i 0
    ~ < i * batch maxpos {
        : f32 v # f32 - ( rnd distinct ) / distinct 2
        ( vec_push [f32] sc v ) ( bytes_push_f32_le raw v )
        = i + i 1
    }
    : GkBuf isc ( gk_dbuf_new kit * batch maxpos GK_F32 )
    : GkBuf sel ( gk_dbuf_new kit * batch maxpos GK_F32 )
    : b _u ( gk_dbuf_upload_bytes kit isc ( slice_from_vec [u] raw ) )
    : ~ ( Vec GkLaunch ) p ( vec_new [GkLaunch] )
    : b ok & ( lk_dsa_select kit != 0 ( nurl_str_eq ( gk_backend kit ) `cuda` ) isc sel npos0 batch maxpos topk p ) ( lk_run p )
    ? ok {} { ( nurl_println `  FAIL the kernel did not run` ) ^ F }
    : ( Vec u ) got ( vec_zeroed [u] * * batch maxpos 4 )
    : b _d ( gk_dbuf_download_bytes kit sel ( slice_from_vec [u] got ) )
    : ( Slice u ) gv ( slice_from_vec [u] got )
    : ~ i b 0
    ~ < b batch {
        : i npos + npos0 b
        : ~ i kept 0
        : ~ i t 0
        ~ < t maxpos {
            : b want ? >= t npos F ? <= npos topk T ( rule_keeps sc * b maxpos npos t topk )
            : b have != 0 ( slice_u32_le gv * 4 + * b maxpos t )
            ? != want have {
                ( nurl_print `  FAIL npos ` ) ( nurl_print_int npos ) ( nurl_print ` topk ` ) ( nurl_print_int topk )
                ( nurl_print ` distinct ` ) ( nurl_print_int distinct ) ( nurl_print ` key ` ) ( nurl_print_int t ) ( nurl_println `` )
                ^ F
            } {}
            ? have { = kept + kept 1 } {}
            = t + t 1
        }
        ? != kept ? <= npos topk npos topk { ( nurl_println `  FAIL the row keeps the wrong number` ) ^ F } {}
        = b + b 1
    }
    ^ T
}

@ timed GpuKit kit i npos i batch i topk → v {
    : i maxpos + npos batch
    : ( Vec u ) raw ( vec_new [u] )
    : ~ i i 0
    ~ < i * batch maxpos { ( bytes_push_f32_le raw # f32 ( rnd 1000003 ) ) = i + i 1 }
    : GkBuf isc ( gk_dbuf_new kit * batch maxpos GK_F32 )
    : GkBuf sel ( gk_dbuf_new kit * batch maxpos GK_F32 )
    : b _u ( gk_dbuf_upload_bytes kit isc ( slice_from_vec [u] raw ) )
    : ~ ( Vec GkLaunch ) p ( vec_new [GkLaunch] )
    : b _r ( lk_dsa_select kit != 0 ( nurl_str_eq ( gk_backend kit ) `cuda` ) isc sel npos batch maxpos topk p )
    : b _w ( lk_run p )
    : i t0 ( monotonic_ns )
    : ~ i r 0
    ~ < r 5 { : b _x ( lk_run p ) = r + r 1 }
    : i dt / - ( monotonic_ns ) t0 5
    ( nurl_print `  npos ` ) ( nurl_print_int npos ) ( nurl_print ` × ` ) ( nurl_print_int batch ) ( nurl_print ` positions: ` ) ( nurl_print_int / dt 1000 ) ( nurl_println ` µs a launch` )
}

@ main → i {
    : GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ( nurl_eprintln `dsa_select_test: no compute device` ) ^ 2 }
    ( nurl_print `backend ` ) ( nurl_println ( gk_backend kit ) )
    : ~ i fails 0
    : ~ i cases 0
    : ( Vec i ) ds ( vec_new [i] ) ( vec_push [i] ds 1000000 ) ( vec_push [i] ds 50 ) ( vec_push [i] ds 3 ) ( vec_push [i] ds 1 )
    : ~ i di 0
    ~ < di ( vec_len [i] ds ) {
        : i d ( vec_at [i] ds di )
        // npos below, at and above topk; one position and a batch.
        ? ( one kit 5 1 64 8 d ) {} { = fails + fails 1 }
        ? ( one kit 8 1 64 8 d ) {} { = fails + fails 1 }
        ? ( one kit 9 1 64 8 d ) {} { = fails + fails 1 }
        ? ( one kit 40 20 64 8 d ) {} { = fails + fails 1 }
        ? ( one kit 300 8 400 37 d ) {} { = fails + fails 1 }
        ? ( one kit 1000 3 1024 999 d ) {} { = fails + fails 1 }
        = cases + cases 6
        = di + di 1
    }
    ( nurl_print `selections: ` ) ( nurl_print_int - cases fails ) ( nurl_print ` of ` ) ( nurl_print_int cases ) ( nurl_println ` cases as the rule` )
    : ( Vec i ) ns ( vec_new [i] ) ( vec_push [i] ns 4096 ) ( vec_push [i] ns 8192 ) ( vec_push [i] ns 16384 ) ( vec_push [i] ns 32768 )
    : ~ i ni 0
    ~ < ni ( vec_len [i] ns ) { ( timed kit ( vec_at [i] ns ni ) 1 2048 ) ( timed kit ( vec_at [i] ns ni ) 64 2048 ) = ni + ni 1 }
    ^ ? == fails 0 0 1
}
