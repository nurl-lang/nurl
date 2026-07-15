// anomaly/score.nu — bulk scoring, version training, and the stateless
// batch path (milestones M2 + M7's GPU acceleration).
//
// Bulk scoring routes through the `gpu` package when profitable:
//
//   - `gpu_open` picks CUDA when a device is present, else the gpu
//     package's CPU backend (the same kernel compiled by the host C++
//     compiler and run under OpenMP). If neither is available — no GPU, no
//     C++ compiler — scoring silently stays on the pure-NURL loop, so a
//     bare machine behaves exactly like pre-GPU builds.
//   - Output is BIT-IDENTICAL across all three paths, by construction: the
//     kernel only walks the trees and accumulates f64 path lengths in the
//     same order as the pure loop, using per-leaf c(size) values
//     precomputed on the host by the very same `iforest_avg_path`; the
//     nonlinear finish (2^(-avg/c), the offset subtraction) runs in NURL
//     either way. IEEE-754 f64 adds in a fixed order give the same bits on
//     every backend — so backend choice can never change a verdict.
//
// `ANOMALY_GPU=0` disables the accelerator outright; `NURL_GPU=cpu` (a gpu
// package knob) forces its CPU backend on a CUDA machine. Batches under
// ANOM_GPU_MIN_ROWS rows skip the accelerator — upload latency would beat
// the win, and bit-equality makes the switch invisible.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/sort.nu`
$ `src/prep.nu`
$ `src/model.nu`
$ `deps/iforest/src/iforest.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`

// Below this many rows the pure loop wins on latency. Bit-equality of the
// paths makes the threshold unobservable in results.
: i ANOM_GPU_MIN_ROWS 128

// Batch verdict over a matrix (see SPEC §6): anomaly ⇔ predict == -1,
// i.e. decision_function < 0 (margin 0), matching the reference batch path.
: BatchReport {
    i total_rows
    i anomaly_count
    f anomaly_percentage
    ( Vec i ) anomaly_indices
    b has_anomalies
    ( Vec f ) scores
}

// ── GPU singleton ─────────────────────────────────────────────────────
//
// One GpuKit (device + kernel cache) per process, probed lazily on the first
// bulk call. The gpukit facade owns the device, the compiled `anomaly_paths`
// kernel (cached), and all the buffer marshalling. state: 0 = unprobed,
// 1 = ready, -1 = unavailable/disabled. The kit pointer is held as an int
// (0 = none), the same way the raw device handle used to be.

: ~ i g_ag_state 0
: ~ i g_ag_kit 0

// The path-walk kernel. One thread per row; per tree, descend by the same
// comparison the pure walker uses and accumulate depth + c(leaf) — nothing
// else, so the f64 sum is bit-identical to the host loop.
@ __ag_kernel_src → s {
    ^ `extern "C" __global__ void anomaly_paths(const double* xs, const long long* feat, const double* split, const long long* left, const long long* right, const double* cleaf, const long long* roots, long long n_rows, long long n_cols, long long n_trees, double* out)
{
    long long r = (long long)blockIdx.x * blockDim.x + threadIdx.x;
    if (r >= n_rows) return;
    const double* x = xs + r * n_cols;
    double total = 0.0;
    for (long long t = 0; t < n_trees; t++) {
        long long node = roots[t];
        long long depth = 0;
        while (feat[node] >= 0) {
            node = (x[feat[node]] < split[node]) ? left[node] : right[node];
            depth++;
        }
        total += (double)depth + cleaf[node];
    }
    out[r] = total;
}
`
}

@ __ag_env_off → b {
    : s v ( getenv `ANOMALY_GPU` )
    ? == # i v 0 { ^ F } {}
    ^ == ( nurl_str_eq v `0` ) 1
}

// Probe once: open a GpuKit (CUDA, else the gpu package's CPU backend) and
// warm the kernel cache with `anomaly_paths`. Any failure parks the
// accelerator for the process.
@ __ag_ensure → b {
    ? != g_ag_state 0 { ^ == g_ag_state 1 } {}
    ? ( __ag_env_off ) {
        = g_ag_state -1
        ^ F
    } {}
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} {
        ( gk_close kit )
        = g_ag_state -1
        ^ F
    }
    ? ( gk_compile kit ( __ag_kernel_src ) `anomaly_paths` ) {} {
        ( gk_close kit )
        = g_ag_state -1
        ^ F
    }
    = g_ag_kit # i kit
    = g_ag_state 1
    ^ T
}

// The live kit (only valid when g_ag_state == 1).
@ __ag_kit → *GpuKit { ^ # *GpuKit g_ag_kit }

// Release the device + kernel cache (tests call this so leak checkers see a
// closed shop; a long-running service just keeps the singleton).
@ anom_gpu_close → v {
    ? == g_ag_state 1 { ( gk_close ( __ag_kit ) ) } {}
    = g_ag_state 0
    = g_ag_kit 0
}

// Which engine bulk scoring would use right now: `cuda`, `cpu` (the gpu
// package's host backend) or `none` (pure NURL loop).
@ anom_gpu_engine → s {
    ? ( __ag_ensure ) {
        ? ( gpu_is_cpu ) { ^ `cpu` } {}
        ^ `cuda`
    } {}
    ^ `none`
}

// ── Bulk raw scores ───────────────────────────────────────────────────

// Pure-NURL reference path: iforest_score per row.
@ anom_scores_cpu VerModel vm ( Vec f ) scaled i n_rows i n_cols → ( Vec f ) {
    : ( Vec f ) out ( vec_with_cap [f] n_rows )
    : ~ i r 0
    ~ < r n_rows {
        ( vec_push [f] out ( iforest_score_row . vm forest scaled r ) )
        = r + r 1
    }
    ^ out
}

// Map a path-length total to the iforest score, matching __score_ptr's
// arithmetic (and its degenerate branches) exactly.
@ __ag_total_to_score f total i n_trees f c_psi → f {
    ? <= n_trees 0 { ^ 0.0 } {}
    ? <= c_psi 0.0 { ^ 0.5 } {}
    : f avg / total # f n_trees
    ^ ( float_pow 2.0 - 0.0 / avg c_psi )
}

// Accelerated path. None when the accelerator is unavailable or any step
// fails (caller falls back; failures after a good probe are reported).
@ anom_scores_gpu VerModel vm ( Vec f ) scaled i n_rows i n_cols → ?( Vec f ) {
    ? ( __ag_ensure ) {} { ^ @ ?( Vec f ) { F } }
    : IForest fo . vm forest
    : i n_trees ( vec_len [i] . fo roots )
    : i n_nodes ( vec_len [i] . fo feature )
    ? || <= n_trees 0 <= n_nodes 0 { ^ @ ?( Vec f ) { F } } {}

    // Per-node c(size), precomputed with the same host function the pure
    // walker calls at each leaf — the kernel only ever adds these values.
    : ( Vec f ) cleaf ( vec_with_cap [f] n_nodes )
    : *i szp ( vec_data [i] . fo size )
    : ~ i k 0
    ~ < k n_nodes {
        ( vec_push [f] cleaf ( iforest_avg_path . szp k ) )
        = k + k 1
    }

    // One gk_run marshals the 7 inputs, 3 scalars and 1 output; the kernel
    // itself (anomaly_paths) is compiled once and served from the kit cache.
    : *GpuKit kit ( __ag_kit )
    : ( Vec f ) totals ( vec_with_cap [f] n_rows )
    : *u outp # *u ( vec_data [f] totals )
    : ( Vec GkArg ) call ( vec_new [GkArg] )
    ( vec_push [GkArg] call ( gk_in_f scaled ) )
    ( vec_push [GkArg] call ( gk_in_i . fo feature ) )
    ( vec_push [GkArg] call ( gk_in_f . fo split ) )
    ( vec_push [GkArg] call ( gk_in_i . fo left ) )
    ( vec_push [GkArg] call ( gk_in_i . fo right ) )
    ( vec_push [GkArg] call ( gk_in_f cleaf ) )
    ( vec_push [GkArg] call ( gk_in_i . fo roots ) )
    ( vec_push [GkArg] call ( gk_i64 n_rows ) )
    ( vec_push [GkArg] call ( gk_i64 n_cols ) )
    ( vec_push [GkArg] call ( gk_i64 n_trees ) )
    ( vec_push [GkArg] call ( gk_buf_out outp * n_rows 8 ) )
    : b ok ( gk_run kit ( __ag_kernel_src ) `anomaly_paths` ( gk_grid n_rows 256 ) 256 call )
    ( vec_free [GkArg] call )
    ( vec_free [f] cleaf )

    ? ok { ( vec_set_len [f] totals n_rows ) } {
        ( vec_free [f] totals )
        ( nurl_eprintln `anomaly: gpu scoring failed, falling back to the pure path` )
        ^ @ ?( Vec f ) { F }
    }

    // Finish on the host, byte-for-byte the pure walker's arithmetic.
    : ( Vec f ) out ( vec_with_cap [f] n_rows )
    : *f tp ( vec_data [f] totals )
    : f cpsi . fo c_psi
    : ~ i r 0
    ~ < r n_rows {
        ( vec_push [f] out ( __ag_total_to_score . tp r n_trees cpsi ) )
        = r + r 1
    }
    ( vec_free [f] totals )
    ^ @ ?( Vec f ) { T out }
}

// Raw iforest scores for every row of an already-standardised matrix,
// through the best available engine. Bit-identical on all engines.
@ anom_scores VerModel vm ( Vec f ) scaled i n_rows i n_cols → ( Vec f ) {
    ? >= n_rows ANOM_GPU_MIN_ROWS {
        : ?( Vec f ) got ( anom_scores_gpu vm scaled n_rows n_cols )
        ?? got {
            T out → { ^ out }
            F _ → {}
        }
    } {}
    ^ ( anom_scores_cpu vm scaled n_rows n_cols )
}

// decision_function for every row: -score - offset, same expression as
// anom_decision.
@ anom_decisions VerModel vm ( Vec f ) scaled i n_rows i n_cols → ( Vec f ) {
    : ( Vec f ) ss ( anom_scores vm scaled n_rows n_cols )
    : *f sp ( vec_data [f] ss )
    : f off . vm offset
    : ~ i r 0
    ~ < r n_rows {
        = . sp r - - 0.0 . sp r off
        = r + r 1
    }
    ^ ss
}

// ── Percentile (numpy 'linear' interpolation, for contamination) ──────

// q in [0,1] over an ASCENDING-sorted vector.
@ _an_percentile ( Vec f ) sorted f q → f {
    : i n ( vec_len [f] sorted )
    ? <= n 0 { ^ 0.0 } {}
    : *f dp ( vec_data [f] sorted )
    ? <= n 1 { ^ . dp 0 } {}
    : ~ f pos * q # f - n 1
    ? < pos 0.0 { = pos 0.0 } {}
    : ~ i lo # i ( float_floor pos )
    ? >= lo - n 1 { ^ . dp - n 1 } {}
    : f frac - pos # f lo
    ^ + . dp lo * - . dp + lo 1 . dp lo frac
}

// ── Version training ──────────────────────────────────────────────────

// Train one version's forest over an ALREADY-STANDARDISED row-major matrix.
// `cfg.max_samples` is clamped to the row count; contamination < 0 = "auto"
// (offset pinned at -0.5), else offset_ is the 100*c percentile of the
// training set's score_samples — so `predict == -1` flags ~c of training.
@ anom_train_version ( Vec f ) scaled i n_rows i n_cols VerCfg cfg → VerModel {
    : ~ i samp . cfg max_samples
    ? > samp n_rows { = samp n_rows } {}
    : IForest fo ( iforest_train scaled n_rows n_cols . cfg n_estimators samp ANOM_SEED )
    : ~ VerModel vm @ VerModel {
        ( string_from ( string_data . cfg vname ) )
        fo
        -0.5
        . cfg decision_margin
        n_cols
        T
    }
    ? >= . cfg contamination 0.0 {
        : ( Vec f ) raw ( anom_scores vm scaled n_rows n_cols )
        : ( Vec f ) ss ( vec_with_cap [f] n_rows )
        : *f rp ( vec_data [f] raw )
        : ~ i r 0
        ~ < r n_rows {
            ( vec_push [f] ss - 0.0 . rp r )
            = r + r 1
        }
        ( vec_free [f] raw )
        ( sort_by [f] ss \ f a f b → i {
            ? < a b { ^ -1 } {}
            ? > a b { ^ 1 } {}
            ^ 0
        } )
        = . vm offset ( _an_percentile ss . cfg contamination )
        ( vec_free [f] ss )
    } {}
    ^ vm
}

// ── Batch (stateless) scoring ─────────────────────────────────────────

// Fit a scaler over the raw matrix, train one version on the standardised
// copy, then score every row. Anomaly ⇔ decision_function <= -cfg.margin
// (margin 0 reproduces the reference's predict == -1 batch rule).
@ anomaly_batch ( Vec f ) data i n_rows i n_cols VerCfg cfg → BatchReport {
    : Scaler sc ( scaler_fit data n_rows n_cols )
    : ( Vec f ) scaled ( vec_clone [f] data )
    ( scaler_apply_matrix sc scaled n_rows n_cols )
    : VerModel vm ( anom_train_version scaled n_rows n_cols cfg )

    : ( Vec f ) scores ( anom_decisions vm scaled n_rows n_cols )
    : ( Vec i ) hits ( vec_new [i] )
    : *f dfp ( vec_data [f] scores )
    : ~ i r 0
    ~ < r n_rows {
        ? ( anom_is_anomaly vm . dfp r ) { ( vec_push [i] hits r ) } {}
        = r + r 1
    }
    ( anom_vermodel_free vm )
    ( vec_free [f] scaled )
    ( scaler_free sc )

    : i n_hits ( vec_len [i] hits )
    : ~ f pct 0.0
    ? > n_rows 0 { = pct / * # f n_hits 100.0 # f n_rows } {}
    ^ @ BatchReport { n_rows n_hits pct hits > n_hits 0 scores }
}

@ anomaly_report_free BatchReport rep → v {
    ( vec_free [i] . rep anomaly_indices )
    ( vec_free [f] . rep scores )
}
