// grad/gpfuse.nu — MEGAKERNEL fusion: generate fused kernels from a
// captured program. The per-node replay's wall on small graphs is GPU-side
// per-kernel latency (~40 small dependent kernels per episode even under a
// CUDA graph); this module derives aegpu's fused shape FROM THE TAPE:
//
//   ROW-SPACE — a node is row-local when output row s depends only on row
//   s of its activation inputs plus whole leaf operands: elementwise
//   add/sub/mul/div ([B,c] with [B,c], [c] or [1]), every unary, and
//   matmul act[B,k] · W[k,c] with W a leaf. A maximal consecutive run of
//   row-local nodes becomes ONE generated kernel: block = row s, threads
//   stride each node's columns in node order, __syncthreads() between
//   nodes. Every node still writes ITS OWN buffer, so readbacks, unfused
//   consumers and gput_set_input work unchanged.
//
//   Everything else (reductions, transpose, bmm, slice/concat, the scalar
//   loss chain) keeps its per-node kernel — a graph that fuses nothing
//   simply runs exactly as before. Execution order is preserved because
//   segments are consecutive id ranges inside the normal walk.
//
// BIT-EXACTNESS: each fused element is computed by one thread with the
// same expression, intrinsics and inner-loop order as the per-node
// kernels, so fused output is bit-identical — the test gates on ==.
//
// The generated source is emitted in f64 with the __d*_rn discipline; an
// f32 program reuses the same substitution pass as the stock kernels
// (type, intrinsics, libm) — kernel names carry a per-plan id, so
// gpukit's name-keyed cache never collides across programs or dtypes.
//
// SAFETY: the passes below write plain CUDA C, reaching node k's value as
// `v<k>` and its gradient as `g<k>` through a table of addresses. That text
// is never launched: __gpf_kernels rewrites every kernel into gpukit's
// checked subset first — `v12[i]` becomes LD(v12, i), `g7[i] = x;` becomes
// ST(g7, i, x);, each v<k> / g<k> a binding of node k's buffer, the early
// `return` guards an enclosing `if` (a block with SYNC() may not leave
// early), every single-statement if / for / while body braced — and the
// launches are recorded (gk_record_dev) once and replayed. A kernel the
// checker refuses fails the plan; none can reach memory outside the
// buffers it is bound to.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`
$ `grad.nu`
$ `gput.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `stdlib/std/arc.nu`

: GpfKern {
    String name
    String body  // the checked body
    ( Vec i ) vids  // v<k> bindings: node k's value
    ( Vec i ) gids  // g<k> bindings: node k's gradient
    b hasb  // takes the row count as `B`
}

: GpPlan {
    b ok
    i kid  // unique plan id baked into kernel names
    i rows  // B — the fused chain's row count
    ( Vec i ) segs  // flattened (lo, hi) inclusive node-id ranges
    String src  // every generated kernel, one source (dtype-adjusted)
    ( Vec String ) knames  // kernel name per segment
    ( Vec String ) bnames  // bwd row-kernel per segment (empty = per-node)
    ( Vec String ) pnames  // bwd param-kernel per segment (empty = none)
    ( Vec i ) pgrid  // param-kernel grid blocks per segment
    ( Vec GpfKern ) ks  // every generated kernel, as a checked body
    ( Vec GkLaunch ) frec  // fused forward launches, recorded on the first forward
    ( Vec GkLaunch ) brec  // fused backward launches, recorded on the first backward
    ( Vec String ) fills  // the gradient zero-fill kernels (one block per gradient)
    String fillk  // fill kernel name
    ( Vec i ) ssegs  // serial-space (lo, hi) ranges — the scalar tail
    ( Vec String ) snames  // serial fwd kernel per serial segment
    ( Vec String ) sbnames  // serial bwd kernel (empty = per-node)
}

// A GpPlan is a handle on its state in an Arc (stdlib/std/arc.nu):
// every copy is the same state, and the last owner releases it.
// The state, for this package's own code.
// Did the analysis find something to fuse?
@ gpfuse_plan_ok inout GpPlan pl → b {
    ^ . pl ok
}

// The fused segments as flattened (lo, hi) inclusive node-id ranges, and
// each segment's backward row-kernel name (empty = per-node). Borrowed:
// valid while the plan is.
@ gpfuse_plan_segs inout GpPlan pl → ( Vec i ) {
    ^ . pl segs
}

@ gpfuse_plan_bnames inout GpPlan pl → ( Vec String ) {
    ^ . pl bnames
}

: ~ i g_gpm_next 1

// ── analysis ─────────────────────────────────────────────────────────

// Is node k row-local over B rows? (see the header for the definition)
@ _gpf_rowlocal inout GProg pg i k i B → b {
    : GpNode nd ( _gp_node pg k )
    ? & == . nd rows B > . nd cols 0 {} { ^ F }
    : i op . nd op
    ? <= op ( gop_const ) { ^ F }
    ? & >= op ( gop_add ) <= op ( gop_div ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        // a must be the [B,c] activation side
        ? & == . na rows B == . na cols . nd cols {} { ^ F }
        // b: same shape, per-row vector [c], or scalar [1]
        ? & == . nb rows B == . nb cols . nd cols { ^ T } {}
        ? & == . nb rows 0 == . nb cols . nd cols { ^ T } {}
        ? == . nb n 1 { ^ T } {}
        ^ F
    } {}
    ? & >= op ( gop_neg ) <= op ( gop_sqrt ) {
        : GpNode na ( _gp_node pg . nd a )
        ^ & == . na rows B == . na cols . nd cols
    } {}
    ? == op ( gop_matmul ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        // activation [B,k] · leaf [k,c]
        ? & == . na rows B > . na cols 0 {} { ^ F }
        ? <= . nb op ( gop_const ) {} { ^ F }
        ^ & == . nb rows . na cols == . nb cols . nd cols
    } {}
    ^ F
}

// ── emission ─────────────────────────────────────────────────────────

@ _gpf_t String o i k → v {
    ( string_push_str o `v` )
    ( string_push_str o ( nurl_str_int k ) )
}

// (double)(<shortest round-trip literal>) — the f32 pass rewrites the cast,
// giving (float)(f64 literal) = the same value our uploads convert to.
@ _gpf_lit String o f v → v {
    ( string_push_str o `(double)(` )
    ( string_push_str o ( nurl_str_float v ) )
    ( string_push_str o `)` )
}

// Declare `const double* v<k>` (or mutable for outputs) from the table.
@ _gpf_decl String o i k b mut → v {
    ( string_push_str o ? mut `    double* ` `    const double* ` )
    ( _gpf_t o k )
    ( string_push_str o ` = (` )
    ( string_push_str o ? mut `double*` `const double*` )
    ( string_push_str o `)(unsigned long long)vt[` )
    ( string_push_str o ( nurl_str_int k ) )
    ( string_push_str o `];\n` )
}

// One fused-segment kernel over nodes [lo, hi].
@ _gpf_emit_seg inout GProg pg i lo i hi i B s kname String o → v {
    ( string_push_str o `extern "C" __global__ void ` )
    ( string_push_str o kname )
    ( string_push_str o `(const long long* vt, long long B)\n{\n` )
    ( string_push_str o `    long long s = blockIdx.x;\n    if (s >= B) return;\n` )
    // buffer views: every referenced node id, outputs mutable
    : ( Vec i ) seen ( vec_new [i] )
    : ~ i k lo
    ~ <= k hi {
        : GpNode nd ( _gp_node pg k )
        ( _gpf_decl o k T )
        ( vec_push [i] seen k )
        : ~ i side 0
        ~ < side 2 {
            : i inid ? == side 0 . nd a . nd b
            ? >= inid 0 {
                : ~ b have F
                ? & >= inid lo <= inid hi { = have T } {}
                : ~ i q 0
                ~ < q ( vec_len [i] seen ) {
                    ? == ( _ti seen q ) inid { = have T } {}
                    = q + q 1
                }
                ? have {} {
                    ( _gpf_decl o inid F )
                    ( vec_push [i] seen inid )
                }
            } {}
            = side + side 1
        }
        = k + k 1
    }
    // node stages
    = k lo
    ~ <= k hi {
        : GpNode nd ( _gp_node pg k )
        : i op . nd op
        : i C . nd cols
        ( string_push_str o `    for (long long c = threadIdx.x; c < ` )
        ( string_push_str o ( nurl_str_int C ) )
        ( string_push_str o `; c += blockDim.x) {\n        ` )
        ? == op ( gop_matmul ) {
            // the gp_matmul inner loop verbatim: serial p, same intrinsics
            : GpNode na ( _gp_node pg . nd a )
            : i K . na cols
            ( string_push_str o `double acc = 0.0;\n        for (long long p = 0; p < ` )
            ( string_push_str o ( nurl_str_int K ) )
            ( string_push_str o `; p++) acc = __dadd_rn(acc, __dmul_rn(` )
            ( _gpf_t o . nd a )
            ( string_push_str o `[s * ` )
            ( string_push_str o ( nurl_str_int K ) )
            ( string_push_str o ` + p], ` )
            ( _gpf_t o . nd b )
            ( string_push_str o `[p * ` )
            ( string_push_str o ( nurl_str_int C ) )
            ( string_push_str o ` + c]));\n        ` )
            ( _gpf_t o k )
            ( string_push_str o `[s * ` )
            ( string_push_str o ( nurl_str_int C ) )
            ( string_push_str o ` + c] = acc` )
        } {
            ( _gpf_t o k )
            ( string_push_str o `[s * ` )
            ( string_push_str o ( nurl_str_int C ) )
            ( string_push_str o ` + c] = ` )
            ( _gpf_expr pg k o )
        }
        ( string_push_str o `;\n    }\n    __syncthreads();\n` )
        = k + k 1
    }
    ( string_push_str o `}\n` )
}

// `a`-side element of a binop/unary at (s, c).
@ _gpf_in String o inout GProg pg i inid i C → v {
    ( _gpf_t o inid )
    ( string_push_str o `[s * ` )
    ( string_push_str o ( nurl_str_int C ) )
    ( string_push_str o ` + c]` )
}

// `b`-side element: matched shape, per-row vector, or scalar.
@ _gpf_inb String o inout GProg pg i inid i C → v {
    : GpNode nb ( _gp_node pg inid )
    ? & == . nb rows 0 == . nb n 1 {
        ( _gpf_t o inid )
        ( string_push_str o `[0]` )
        ^ v
    } {}
    ? == . nb rows 0 {
        ( _gpf_t o inid )
        ( string_push_str o `[c]` )
        ^ v
    } {}
    ( _gpf_in o pg inid C )
}

// The per-element expression for fused node k — the EXACT per-node kernel
// arithmetic (gp_ew_bc / gp_scal / gp_trans / gp_matmul), spelled inline.
@ _gpf_expr inout GProg pg i k String o → v {
    : GpNode nd ( _gp_node pg k )
    : i op . nd op
    : i C . nd cols
    ? == op ( gop_add ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_inb o pg . nd b C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_sub ) { ( string_push_str o `__dsub_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_inb o pg . nd b C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_mul ) { ( string_push_str o `__dmul_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_inb o pg . nd b C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_div ) { ( string_push_str o `__ddiv_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_inb o pg . nd b C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_neg ) { ( string_push_str o `__dsub_rn((double)(0), ` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_adds ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_lit o . nd s ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_muls ) { ( string_push_str o `__dmul_rn(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `, ` ) ( _gpf_lit o . nd s ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_relu ) { ( _gpf_in o pg . nd a C ) ( string_push_str o ` > (double)(0) ? ` ) ( _gpf_in o pg . nd a C ) ( string_push_str o ` : (double)(0)` ) ^ v } {}
    ? == op ( gop_sigmoid ) { ( string_push_str o `__ddiv_rn(1.0, __dadd_rn(1.0, exp(__dsub_rn(0.0, ` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `))))` ) ^ v } {}
    ? == op ( gop_tanh ) {
        // two-step form via a statement expression is non-portable; inline:
        // e2 appears twice — identical exp() calls, same rounding.
        ( string_push_str o `__ddiv_rn(__dsub_rn(exp(__dmul_rn((double)(2), ` )
        ( _gpf_in o pg . nd a C )
        ( string_push_str o `)), (double)(1)), __dadd_rn(exp(__dmul_rn((double)(2), ` )
        ( _gpf_in o pg . nd a C )
        ( string_push_str o `)), (double)(1)))` )
        ^ v
    } {}
    ? == op ( gop_exp ) { ( string_push_str o `exp(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_log ) { ( string_push_str o `log(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_sqrt ) { ( string_push_str o `sqrt(` ) ( _gpf_in o pg . nd a C ) ( string_push_str o `)` ) ^ v } {}
    ( string_push_str o `0.0 /* unreachable */` )
}

// ── the plan ─────────────────────────────────────────────────────────

// Let go of `pl` now rather than at the end of its owner's scope. A plan
// owns its kernel names and sources and its device tables, and releases
// them with its last owner.
@ gpfuse_free sink GpPlan pl → v {}

// Analyze the program, emit the fused-forward kernels, upload the pointer
// table. ok=F (with everything freed safe) when nothing fuses.
@ gpfuse_plan inout GProg pg → GpPlan {
    : ~ GpPlan pl @ GpPlan { F g_gpm_next 0 ( vec_new [i] ) ( string_new ) ( vec_new [String] ) ( vec_new [String] )
        ( vec_new [String] ) ( vec_new [i] ) ( vec_new [GpfKern] ) ( vec_new [GkLaunch] ) ( vec_new [GkLaunch] ) ( vec_new [String] ) ( string_new )
        ( vec_new [i] ) ( vec_new [String] ) ( vec_new [String] ) }
    = g_gpm_next + g_gpm_next 1
    ? . pg ok {} { ^ pl }
    // B = the most common 2-D row count among non-leaf nodes (the batch)
    : i nn ( vec_len [GpNode] . pg nodes )
    : ~ i B 0
    : ~ i bestc 0
    : ~ i k 0
    ~ < k nn {
        : GpNode nd ( _gp_node pg k )
        ? & > . nd op ( gop_const ) > . nd rows 0 {
            : ~ i cnt 0
            : ~ i j 0
            ~ < j nn {
                : GpNode m ( _gp_node pg j )
                ? & > . m op ( gop_const ) == . m rows . nd rows { = cnt + cnt 1 } {}
                = j + j 1
            }
            ? > cnt bestc { = bestc cnt = B . nd rows } {}
        } {}
        = k + k 1
    }
    ? > B 0 {} { ^ pl }
    = . pl rows B
    // maximal consecutive fusable runs (length >= 2)
    = k 0
    ~ < k nn {
        ? ( _gpf_rowlocal pg k B ) {
            : ~ i hi k
            ~ & < + hi 1 nn ( _gpf_rowlocal pg + hi 1 B ) { = hi + hi 1 }
            ? > hi k {
                ( vec_push [i] . pl segs k )
                ( vec_push [i] . pl segs hi )
            } {}
            = k + hi 1
        } { = k + k 1 }
    }
    ? > ( vec_len [i] . pl segs ) 0 {} { ^ pl }
    // emit every segment kernel
    : i nseg / ( vec_len [i] . pl segs ) 2
    = k 0
    ~ < k nseg {
        : String nm ( string_from `gpm` )
        ( string_push_str nm ( nurl_str_int . pl kid ) )
        ( string_push_str nm ? == . pg dtype 1 `f` `d` )
        ( string_push_str nm `_s` )
        ( string_push_str nm ( nurl_str_int k ) )
        ( _gpf_emit_seg pg ( _ti . pl segs * k 2 ) ( _ti . pl segs + * k 2 1 ) B ( string_data nm ) . pl src )
        ( vec_push [String] . pl knames nm )
        = k + k 1
    }
    // backward: row-space + param-space kernels per segment (order-safe
    // segments only), plus the one-launch gradient fill
    = k 0
    ~ < k nseg {
        : i lo ( _ti . pl segs * k 2 )
        : i hi ( _ti . pl segs + * k 2 1 )
        : String bn ( string_new )
        : String pn ( string_new )
        : ~ i pgr 0
        ? ( _gpf_bwd_ok pg lo hi B ) {
            : String cand ( string_from `gpm` )
            ( string_push_str cand ( nurl_str_int . pl kid ) )
            ( string_push_str cand ? == . pg dtype 1 `f` `d` )
            ( string_push_str cand `_b` )
            ( string_push_str cand ( nurl_str_int k ) )
            ? ( _gpf_emit_bwd_seg pg lo hi B ( string_data cand ) . pl src ) {
                ( string_push_str bn ( string_data cand ) )
                : String pc ( string_from `gpm` )
                ( string_push_str pc ( nurl_str_int . pl kid ) )
                ( string_push_str pc ? == . pg dtype 1 `f` `d` )
                ( string_push_str pc `_p` )
                ( string_push_str pc ( nurl_str_int k ) )
                : i mx ( _gpf_emit_param_seg pg lo hi B ( string_data pc ) . pl src )
                ? > mx 0 {
                    ( string_push_str pn ( string_data pc ) )
                    = pgr ( gk_grid mx 256 )
                } {}
            } {}
        } {}
        ( vec_push [String] . pl bnames bn )
        ( vec_push [String] . pl pnames pn )
        ( vec_push [i] . pl pgrid pgr )
        = k + k 1
    }
    // serial-space segments claim the leftovers (the scalar tail)
    = k 0
    ~ < k nn {
        ? & == ( _gpf_in_rowseg pl k ) F ( _gpf_serial_ok pg k ) {
            : ~ i hi2 k
            ~ & < + hi2 1 nn & == ( _gpf_in_rowseg pl + hi2 1 ) F ( _gpf_serial_ok pg + hi2 1 ) { = hi2 + hi2 1 }
            ? > hi2 k {
                ( vec_push [i] . pl ssegs k )
                ( vec_push [i] . pl ssegs hi2 )
            } {}
            = k + hi2 1
        } { = k + k 1 }
    }
    : i nser / ( vec_len [i] . pl ssegs ) 2
    = k 0
    ~ < k nser {
        : i slo ( _ti . pl ssegs * k 2 )
        : i shi ( _ti . pl ssegs + * k 2 1 )
        : String sn ( string_from `gpm` )
        ( string_push_str sn ( nurl_str_int . pl kid ) )
        ( string_push_str sn ? == . pg dtype 1 `f` `d` )
        ( string_push_str sn `_t` )
        ( string_push_str sn ( nurl_str_int k ) )
        : b _e ( _gpf_emit_ser_seg pg slo shi ( string_data sn ) . pl src )
        ( vec_push [String] . pl snames sn )
        : String sb ( string_new )
        : String cand2 ( string_from `gpm` )
        ( string_push_str cand2 ( nurl_str_int . pl kid ) )
        ( string_push_str cand2 ? == . pg dtype 1 `f` `d` )
        ( string_push_str cand2 `_u` )
        ( string_push_str cand2 ( nurl_str_int k ) )
        ? ( _gpf_emit_ser_bwd_seg pg slo shi ( string_data cand2 ) . pl src ) {
            ( string_push_str sb ( string_data cand2 ) )
        } {}
        ( vec_push [String] . pl sbnames sb )
        = k + k 1
    }

    ( string_push_str . pl fillk `gpm` )
    ( string_push_str . pl fillk ( nurl_str_int . pl kid ) )
    ( string_push_str . pl fillk ? == . pg dtype 1 `f` `d` )
    ( string_push_str . pl fillk `_fill` )
    ( _gpf_emit_fills pg pl )

    // dtype adjustment: the same substitution pass the stock kernels use
    ? == . pg dtype 1 {
        : ~ String x ( _str_replace_all ( string_data . pl src ) `__dadd_rn` `__fadd_rn` )
        = x ( _str_replace_all ( string_data x ) `__dsub_rn` `__fsub_rn` )
        = x ( _str_replace_all ( string_data x ) `__dmul_rn` `__fmul_rn` )
        = x ( _str_replace_all ( string_data x ) `__ddiv_rn` `__fdiv_rn` )
        = x ( _str_replace_all ( string_data x ) `exp(` `expf(` )
        = x ( _str_replace_all ( string_data x ) `log(` `logf(` )
        = x ( _str_replace_all ( string_data x ) `sqrt(` `sqrtf(` )
        = x ( _str_replace_all ( string_data x ) `double` `float` )
        = . pl src x
    } {}
    // every kernel into the checked subset (nothing is launched from the
    // C text itself)
    = . pl ks ( __gpf_kernels ( string_data . pl src ) )
    : ~ b up > ( vec_len [GpfKern] . pl ks ) 0
    ? up { = . pl ok T } {}
    ^ pl
}

// Launches only (no sync policy) — shared by the direct path and the
// CUDA-graph capture.
@ _gpfuse_fwd_launches inout GProg pg inout GpPlan pl → b {
    : i nn ( vec_len [GpNode] . pg nodes )
    : i nseg / ( vec_len [i] . pl segs ) 2
    : ~ b r T
    : ~ i k 0
    : ~ i si 0
    : ~ i ri 0
    ~ & < k nn r {
        ? & < si nseg == k ( _ti . pl segs * si 2 ) {
            : s nm ?? ( vec_get [String] . pl knames si ) { T x → ( string_data x ) F → `` }
            = r ( _gpf_run pg . pl ks . pl frec ri nm . pl rows . pl rows 256 )
            = k + ( _ti . pl segs + * si 2 1 ) 1
            = si + si 1
        } {
            : ~ i ssi -1
            : i nser2 / ( vec_len [i] . pl ssegs ) 2
            : ~ i w2 0
            ~ < w2 nser2 {
                ? == ( _ti . pl ssegs * w2 2 ) k { = ssi w2 } {}
                = w2 + w2 1
            }
            ? >= ssi 0 {
                : s sn2 ?? ( vec_get [String] . pl snames ssi ) { T x → ( string_data x ) F → `` }
                = r ( _gpf_run pg . pl ks . pl frec ri sn2 . pl rows 1 256 )
                = k + ( _ti . pl ssegs + * ssi 2 1 ) 1
            } {
                = r ( _gp_fwd_node pg k )
                = k + k 1
            }
        }
    }
    ^ r
}

// Fused forward: segments as one kernel each, everything else per-node.
@ gpfuse_forward inout GProg pg inout GpPlan pl → b {
    ? & . pg ok . pl ok {} { ^ F }
    ( gk_autosync F )
    : b r ( _gpfuse_fwd_launches pg pl )
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}

// ── backward emission ────────────────────────────────────────────────
// Row-space gradient stages (dActivations) fuse into one kernel per
// segment, sweeping nodes hi→lo with __syncthreads between stages — the
// same launch order as the per-node reverse walk. Param-space targets
// (matmul leaf weights, broadcast ew operands) accumulate SERIALLY over
// rows per element — gp_bw_mm_b / gp_bw_accred verbatim — in a second
// kernel launched after the row kernel. A gradient element only ever
// belongs to one class, so the split preserves bit order; the one corner
// where a target could collect BOTH kinds inside a segment is detected
// by _gpf_bwd_ok and that segment honestly falls back to per-node.

@ _gpf_g String o i k → v {
    ( string_push_str o `g` )
    ( string_push_str o ( nurl_str_int k ) )
}

// double* g<k> = (double*)(unsigned long long)gt[<k>];
@ _gpf_gdecl String o i k → v {
    ( string_push_str o `    double* ` )
    ( _gpf_g o k )
    ( string_push_str o ` = (double*)(unsigned long long)gt[` )
    ( string_push_str o ( nurl_str_int k ) )
    ( string_push_str o `];\n` )
}

@ _gpf_seen ( Vec i ) seen i id → b {
    : ~ i q 0
    ~ < q ( vec_len [i] seen ) {
        ? == ( _ti seen q ) id { ^ T } {}
        = q + q 1
    }
    ( vec_push [i] seen id )
    ^ F
}

// g<id>[s * C + c]
@ _gpf_gel String o i id i C → v {
    ( _gpf_g o id )
    ( string_push_str o `[s * ` )
    ( string_push_str o ( nurl_str_int C ) )
    ( string_push_str o ` + c]` )
}

// Is ew input `inid` the same [B,c] shape as consumer `nd`?
@ _gpf_same inout GProg pg i inid i B i C → b {
    : GpNode m ( _gp_node pg inid )
    ^ & == . m rows B == . m cols C
}

// accred wrapper: TARGET = __dadd_rn(TARGET, __dmul_rn(<sgn>, <src...>
@ _gpf_acc_open String o inout GProg pg i tid i C s sgn → v {
    ( string_push_str o `        ` )
    ( _gpf_gel o tid C )
    ( string_push_str o ` = __dadd_rn(` )
    ( _gpf_gel o tid C )
    ( string_push_str o `, __dmul_rn(` )
    ( string_push_str o sgn )
    ( string_push_str o `, ` )
}

// One row-space backward stage loop `for c < W` around `body` pushes.
@ _gpf_stage_open String o i W → v {
    ( string_push_str o `    for (long long c = threadIdx.x; c < ` )
    ( string_push_str o ( nurl_str_int W ) )
    ( string_push_str o `; c += blockDim.x) {\n` )
}

@ _gpf_stage_close String o → v {
    ( string_push_str o `    }\n    __syncthreads();\n` )
}

// Row-space bwd kernel body for segment [lo,hi]; stage count returned.
@ _gpf_emit_bwd_stages inout GProg pg i lo i hi i B String o ( Vec i ) vids ( Vec i ) gids → i {
    : ~ i stages 0
    : ~ i k hi
    ~ >= k lo {
        : GpNode nd ( _gp_node pg k )
        : i op . nd op
        : i C . nd cols
        ? == . nd reach 1 {
            ? & >= op ( gop_add ) <= op ( gop_div ) {
                : GpNode na ( _gp_node pg . nd a )
                : GpNode nb ( _gp_node pg . nd b )
                : b needa == . na reach 1
                : ~ b needb F
                ? & ( _gpf_same pg . nd b B C ) == . nb reach 1 { = needb T } {}
                ? | needa needb {
                    = stages + stages 1
                    : b _s ( _gpf_seen gids k )
                    ( _gpf_stage_open o C )
                    ? needa {
                        : b _t ( _gpf_seen gids . nd a )
                        ( _gpf_acc_open o pg . nd a C `1.0` )
                        ? == op ( gop_add ) { ( _gpf_gel o k C ) } {}
                        ? == op ( gop_sub ) { ( _gpf_gel o k C ) } {}
                        ? == op ( gop_mul ) {
                            : b _v ( _gpf_seen vids . nd b )
                            ( string_push_str o `__dmul_rn(` )
                            ( _gpf_gel o k C )
                            ( string_push_str o `, ` )
                            ( _gpf_inb o pg . nd b C )
                            ( string_push_str o `)` )
                        } {}
                        ? == op ( gop_div ) {
                            : b _v ( _gpf_seen vids . nd b )
                            ( string_push_str o `__ddiv_rn(` )
                            ( _gpf_gel o k C )
                            ( string_push_str o `, ` )
                            ( _gpf_inb o pg . nd b C )
                            ( string_push_str o `)` )
                        } {}
                        ( string_push_str o `));\n` )
                    } {}
                    ? needb {
                        : b _t ( _gpf_seen gids . nd b )
                        : s sg2 ? == op ( gop_sub ) `-1.0` ? == op ( gop_div ) `-1.0` `1.0`
                        ( _gpf_acc_open o pg . nd b C sg2 )
                        ? == op ( gop_add ) { ( _gpf_gel o k C ) } {}
                        ? == op ( gop_sub ) { ( _gpf_gel o k C ) } {}
                        ? == op ( gop_mul ) {
                            : b _v ( _gpf_seen vids . nd a )
                            ( string_push_str o `__dmul_rn(` )
                            ( _gpf_gel o k C )
                            ( string_push_str o `, ` )
                            ( _gpf_in o pg . nd a C )
                            ( string_push_str o `)` )
                        } {}
                        ? == op ( gop_div ) {
                            // scr = (g ⊙ out) / b — gp_bw's exact chain
                            : b _v ( _gpf_seen vids k )
                            : b _v2 ( _gpf_seen vids . nd b )
                            ( string_push_str o `__ddiv_rn(__dmul_rn(` )
                            ( _gpf_gel o k C )
                            ( string_push_str o `, ` )
                            ( _gpf_in o pg k C )
                            ( string_push_str o `), ` )
                            ( _gpf_inb o pg . nd b C )
                            ( string_push_str o `)` )
                        } {}
                        ( string_push_str o `));\n` )
                    } {}
                    ( _gpf_stage_close o )
                } {}
            } {}
            ? & >= op ( gop_neg ) <= op ( gop_sqrt ) {
                : GpNode na ( _gp_node pg . nd a )
                ? == . na reach 1 {
                    = stages + stages 1
                    : b _s ( _gpf_seen gids k )
                    : b _t ( _gpf_seen gids . nd a )
                    ( _gpf_stage_open o C )
                    ( string_push_str o `        double gi = ` )
                    ( _gpf_gel o k C )
                    ( string_push_str o `;\n        ` )
                    ( _gpf_gel o . nd a C )
                    ( string_push_str o ` = ` )
                    // gp_bw_unary's exact per-op accumulate expression
                    ? == op ( gop_neg ) {
                        ( string_push_str o `__dsub_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, gi)` )
                    } {}
                    ? == op ( gop_adds ) {
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, gi)` )
                    } {}
                    ? == op ( gop_muls ) {
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __dmul_rn(gi, ` )
                        ( _gpf_lit o . nd s )
                        ( string_push_str o `))` )
                    } {}
                    ? == op ( gop_relu ) {
                        : b _v ( _gpf_seen vids k )
                        ( _gpf_in o pg k C )
                        ( string_push_str o ` > 0.0 ? __dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, gi) : ` )
                        ( _gpf_gel o . nd a C )
                    } {}
                    ? == op ( gop_sigmoid ) {
                        : b _v ( _gpf_seen vids k )
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __dmul_rn(gi, __dmul_rn(` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `, __dsub_rn(1.0, ` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `))))` )
                    } {}
                    ? == op ( gop_tanh ) {
                        : b _v ( _gpf_seen vids k )
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __dmul_rn(gi, __dsub_rn(1.0, __dmul_rn(` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `, ` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `))))` )
                    } {}
                    ? == op ( gop_exp ) {
                        : b _v ( _gpf_seen vids k )
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __dmul_rn(gi, ` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `))` )
                    } {}
                    ? == op ( gop_log ) {
                        : b _v ( _gpf_seen vids . nd a )
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __ddiv_rn(gi, ` )
                        ( _gpf_in o pg . nd a C )
                        ( string_push_str o `))` )
                    } {}
                    ? == op ( gop_sqrt ) {
                        : b _v ( _gpf_seen vids k )
                        ( string_push_str o `__dadd_rn(` )
                        ( _gpf_gel o . nd a C )
                        ( string_push_str o `, __ddiv_rn(gi, __dmul_rn(2.0, ` )
                        ( _gpf_in o pg k C )
                        ( string_push_str o `)))` )
                    } {}
                    ( string_push_str o `;\n` )
                    ( _gpf_stage_close o )
                } {}
            } {}
            ? == op ( gop_matmul ) {
                : GpNode na ( _gp_node pg . nd a )
                ? == . na reach 1 {
                    = stages + stages 1
                    : b _s ( _gpf_seen gids k )
                    : b _t ( _gpf_seen gids . nd a )
                    : b _v ( _gpf_seen vids . nd b )
                    : i K . na cols
                    : i N2 . nd cols
                    // gp_bw_mm_a verbatim: dA[s,p] += Σ_j g[s,j]·W[p,j]
                    ( _gpf_stage_open o K )
                    ( string_push_str o `        double acc = 0.0;\n        for (long long j = 0; j < ` )
                    ( string_push_str o ( nurl_str_int N2 ) )
                    ( string_push_str o `; j++) acc = __dadd_rn(acc, __dmul_rn(` )
                    ( _gpf_g o k )
                    ( string_push_str o `[s * ` )
                    ( string_push_str o ( nurl_str_int N2 ) )
                    ( string_push_str o ` + j], ` )
                    ( _gpf_t o . nd b )
                    ( string_push_str o `[c * ` )
                    ( string_push_str o ( nurl_str_int N2 ) )
                    ( string_push_str o ` + j]));\n        ` )
                    ( _gpf_gel o . nd a K )
                    ( string_push_str o ` = __dadd_rn(` )
                    ( _gpf_gel o . nd a K )
                    ( string_push_str o `, acc);\n` )
                    ( _gpf_stage_close o )
                } {}
            } {}
        } {}
        = k - k 1
    }
    ^ stages
}

// Param-space jobs of segment [lo,hi], descending consumer order, encoded
// as (target, kind, consumer) triples — kind 0 = matmul dW, 1 = ew b-side.
@ _gpf_param_jobs inout GProg pg i lo i hi i B ( Vec i ) jobs → v {
    : ~ i k hi
    ~ >= k lo {
        : GpNode nd ( _gp_node pg k )
        : i op . nd op
        ? == . nd reach 1 {
            ? & >= op ( gop_add ) <= op ( gop_div ) {
                : GpNode nb ( _gp_node pg . nd b )
                ? & == . nb reach 1 == ( _gpf_same pg . nd b B . nd cols ) F {
                    ( vec_push [i] jobs . nd b )
                    ( vec_push [i] jobs 1 )
                    ( vec_push [i] jobs k )
                } {}
            } {}
            ? == op ( gop_matmul ) {
                : GpNode nb ( _gp_node pg . nd b )
                ? == . nb reach 1 {
                    ( vec_push [i] jobs . nd b )
                    ( vec_push [i] jobs 0 )
                    ( vec_push [i] jobs k )
                } {}
            } {}
        } {}
        = k - k 1
    }
}

// Order safety: no gradient may collect BOTH row-space and param-space
// contributions inside one segment (the split would reorder them).
@ _gpf_bwd_ok inout GProg pg i lo i hi i B → b {
    : ( Vec i ) rowt ( vec_new [i] )
    : ~ i k lo
    ~ <= k hi {
        : GpNode nd ( _gp_node pg k )
        : i op . nd op
        ? == . nd reach 1 {
            ? > op ( gop_const ) {
                : GpNode na ( _gp_node pg . nd a )
                ? == . na reach 1 { : b _x ( _gpf_seen rowt . nd a ) } {}
                ? & >= op ( gop_add ) <= op ( gop_div ) {
                    : GpNode nb ( _gp_node pg . nd b )
                    ? & ( _gpf_same pg . nd b B . nd cols ) == . nb reach 1 {
                        : b _y ( _gpf_seen rowt . nd b )
                    } {}
                } {}
            } {}
        } {}
        = k + k 1
    }
    : ( Vec i ) jobs ( vec_new [i] )
    ( _gpf_param_jobs pg lo hi B jobs )
    : ~ b ok T
    : ~ i q 0
    ~ < q ( vec_len [i] jobs ) {
        : i tid ( _ti jobs q )
        : ~ i w 0
        ~ < w ( vec_len [i] rowt ) {
            ? == ( _ti rowt w ) tid { = ok F } {}
            = w + w 1
        }
        = q + q 3
    }
    ^ ok
}

// The param-space kernel: one grid-stride stage per distinct target, jobs
// serial inside each thread — gp_bw_mm_b / gp_bw_accred element order.
// Returns the widest target n (grid sizing); 0 when there are no jobs.
@ _gpf_emit_param inout GProg pg i lo i hi i B String body ( Vec i ) vids ( Vec i ) gids → i {
    : ( Vec i ) jobs ( vec_new [i] )
    ( _gpf_param_jobs pg lo hi B jobs )
    : i nj / ( vec_len [i] jobs ) 3
    ? > nj 0 {} { ^ 0 }
    : ~ i maxn 0
    : ( Vec i ) done ( vec_new [i] )
    : ~ i q 0
    ~ < q nj {
        : i tid ( _ti jobs * q 3 )
        ? ( _gpf_seen done tid ) { = q + q 1 } {
            : GpNode nt ( _gp_node pg tid )
            : b _g ( _gpf_seen gids tid )
            ? > . nt n maxn { = maxn . nt n } {}
            ( string_push_str body `    for (long long t = (long long)blockIdx.x * blockDim.x + threadIdx.x; t < ` )
            ( string_push_str body ( nurl_str_int . nt n ) )
            ( string_push_str body `; t += (long long)gridDim.x * blockDim.x) {\n` )
            // every job hitting this target, in collected (descending) order
            : ~ i w 0
            ~ < w nj {
                ? == ( _ti jobs * w 3 ) tid {
                    : i kind ( _ti jobs + * w 3 1 )
                    : i kc ( _ti jobs + * w 3 2 )
                    : GpNode nd ( _gp_node pg kc )
                    : i C . nd cols
                    : b _gk ( _gpf_seen gids kc )
                    ? == kind 0 {
                        // gp_bw_mm_b: dW[p,j] += Σ_i A[i,p]·g[i,j], serial i
                        : GpNode na ( _gp_node pg . nd a )
                        : i K . na cols
                        : b _va ( _gpf_seen vids . nd a )
                        ( string_push_str body `        { long long p = t / ` )
                        ( string_push_str body ( nurl_str_int C ) )
                        ( string_push_str body `, j = t % ` )
                        ( string_push_str body ( nurl_str_int C ) )
                        ( string_push_str body `;\n          double acc = 0.0;\n          for (long long i = 0; i < ` )
                        ( string_push_str body ( nurl_str_int B ) )
                        ( string_push_str body `; i++) acc = __dadd_rn(acc, __dmul_rn(` )
                        ( _gpf_t body . nd a )
                        ( string_push_str body `[i * ` )
                        ( string_push_str body ( nurl_str_int K ) )
                        ( string_push_str body ` + p], ` )
                        ( _gpf_g body kc )
                        ( string_push_str body `[i * ` )
                        ( string_push_str body ( nurl_str_int C ) )
                        ( string_push_str body ` + j]));\n          ` )
                        ( _gpf_g body tid )
                        ( string_push_str body `[t] = __dadd_rn(` )
                        ( _gpf_g body tid )
                        ( string_push_str body `[t], acc); }\n` )
                    } {
                        // gp_bw_accred: serial odometer over the B rows (or
                        // all B·C elements for a scalar target)
                        : i op . nd op
                        : b scal == . nt n 1
                        : i tf ? scal * B C B
                        : s sgn ? | == op ( gop_sub ) == op ( gop_div ) `-1.0` `1.0`
                        ( string_push_str body `        { double g0 = ` )
                        ( _gpf_g body tid )
                        ( string_push_str body `[t];\n          for (long long q = 0; q < ` )
                        ( string_push_str body ( nurl_str_int tf ) )
                        ( string_push_str body `; q++) g0 = __dadd_rn(g0, __dmul_rn(` )
                        ( string_push_str body sgn )
                        ( string_push_str body `, ` )
                        // the source element at flat q (scalar) / (q, t) (vector)
                        : String ix ( string_new )
                        ? scal {
                            ( string_push_str ix `[q]` )
                        } {
                            ( string_push_str ix `[q * ` )
                            ( string_push_str ix ( nurl_str_int C ) )
                            ( string_push_str ix ` + t]` )
                        }
                        ? == op ( gop_mul ) {
                            : b _va ( _gpf_seen vids . nd a )
                            ( string_push_str body `__dmul_rn(` )
                            ( _gpf_g body kc )
                            ( string_push_str body ( string_data ix ) )
                            ( string_push_str body `, ` )
                            ( _gpf_t body . nd a )
                            ( string_push_str body ( string_data ix ) )
                            ( string_push_str body `)` )
                        } {
                            ? == op ( gop_div ) {
                                : b _vk ( _gpf_seen vids kc )
                                : b _vt ( _gpf_seen vids tid )
                                ( string_push_str body `__ddiv_rn(__dmul_rn(` )
                                ( _gpf_g body kc )
                                ( string_push_str body ( string_data ix ) )
                                ( string_push_str body `, ` )
                                ( _gpf_t body kc )
                                ( string_push_str body ( string_data ix ) )
                                ( string_push_str body `), ` )
                                ( _gpf_t body tid )
                                ( string_push_str body ? scal `[0]` `[t]` )
                                ( string_push_str body `)` )
                            } {
                                ( _gpf_g body kc )
                                ( string_push_str body ( string_data ix ) )
                            }
                        }
                        ( string_push_str body `));\n          ` )
                        ( _gpf_g body tid )
                        ( string_push_str body `[t] = g0; }\n` )
                    }
                } {}
                = w + w 1
            }
            ( string_push_str body `    }\n` )
            = q + q 1
        }
    }
    ^ maxn
}

// Assemble the row-space bwd kernel; F when the segment has no stages.
@ _gpf_emit_bwd_seg inout GProg pg i lo i hi i B s kname String o → b {
    : String body ( string_new )
    : ( Vec i ) vids ( vec_new [i] )
    : ( Vec i ) gids ( vec_new [i] )
    : i stages ( _gpf_emit_bwd_stages pg lo hi B body vids gids )
    ? > stages 0 {} {
        ^ F
    }
    ( string_push_str o `extern "C" __global__ void ` )
    ( string_push_str o kname )
    ( string_push_str o `(const long long* vt, const long long* gt, long long B)\n{\n` )
    ( string_push_str o `    long long s = blockIdx.x;\n    if (s >= B) return;\n` )
    : ~ i q 0
    ~ < q ( vec_len [i] vids ) {
        ( _gpf_decl o ( _ti vids q ) F )
        = q + q 1
    }
    = q 0
    ~ < q ( vec_len [i] gids ) {
        ( _gpf_gdecl o ( _ti gids q ) )
        = q + q 1
    }
    ( string_push_str o ( string_data body ) )
    ( string_push_str o `}\n` )
    ^ T
}

// Assemble the param-space kernel; returns the widest target n (0 = none).
@ _gpf_emit_param_seg inout GProg pg i lo i hi i B s kname String o → i {
    : String body ( string_new )
    : ( Vec i ) vids ( vec_new [i] )
    : ( Vec i ) gids ( vec_new [i] )
    : i maxn ( _gpf_emit_param pg lo hi B body vids gids )
    ? > maxn 0 {} {
        ^ 0
    }
    ( string_push_str o `extern "C" __global__ void ` )
    ( string_push_str o kname )
    ( string_push_str o `(const long long* vt, const long long* gt)\n{\n` )
    : ~ i q 0
    ~ < q ( vec_len [i] vids ) {
        ( _gpf_decl o ( _ti vids q ) F )
        = q + q 1
    }
    = q 0
    ~ < q ( vec_len [i] gids ) {
        ( _gpf_gdecl o ( _ti gids q ) )
        = q + q 1
    }
    ( string_push_str o ( string_data body ) )
    ( string_push_str o `}\n` )
    ^ maxn
}

// The gradient zero fill: one block per gradient buffer, in kernels of
// at most 64 gradients each (named fillk_<n>, listed in pl.fills).
@ _gpf_emit_fills inout GProg pg inout GpPlan pl → v {
    : i nn ( vec_len [GpNode] . pg nodes )
    : ~ ( Vec i ) gs ( vec_new [i] )
    : ~ i k 0
    ~ < k nn {
        : GpNode nd ( _gp_node pg k )
        ? ( gk_buf_ok . nd grad ) { ( vec_push [i] gs k ) } {}
        = k + k 1
    }
    : i ng ( vec_len [i] gs )
    : ~ i c0 0
    ~ < c0 ng {
        : i c1 ? > + c0 64 ng ng + c0 64
        : ~ String nm ( string_from ( string_data . pl fillk ) )
        ( string_push_char nm 95 ) ( string_push_int nm / c0 64 )
        ( string_push_str . pl src `extern "C" __global__ void ` )
        ( string_push_str . pl src ( string_data nm ) )
        ( string_push_str . pl src `(const long long* vt, const long long* gt)\n{\n` )
        = k c0
        ~ < k c1 { ( _gpf_gdecl . pl src ( _ti gs k ) ) = k + k 1 }
        = k c0
        ~ < k c1 {
            : GpNode nd ( _gp_node pg ( _ti gs k ) )
            ( string_push_str . pl src `    if (blockIdx.x == ` ) ( string_push_int . pl src - k c0 )
            ( string_push_str . pl src `) { for (long long t = threadIdx.x; t < ` ) ( string_push_int . pl src . nd n )
            ( string_push_str . pl src `; t += blockDim.x) ` ) ( _gpf_g . pl src ( _ti gs k ) ) ( string_push_str . pl src `[t] = 0.0; }\n` )
            = k + k 1
        }
        ( string_push_str . pl src `}\n` )
        ( vec_push [String] . pl fills nm )
        = c0 c1
    }
}

// ── the generated source, into checked kernels ───────────────────────

@ __gpf_dig i c → b { ^ & >= c 48 <= c 57 }

@ __gpf_idc i c → b { ^ | | & >= c 97 <= c 122 & >= c 65 <= c 90 | == c 95 ( __gpf_dig c ) }

// The closer matching the opener at `open` — over ( ) [ ] { }.
@ __gpf_match ( Slice u ) t i open i hi → i {
    : ~ i d 0
    : ~ i k open
    ~ < k hi {
        : i c ( slice_byte t k )
        ? | | == c 40 == c 91 == c 123 { = d + d 1 } {}
        ? | | == c 41 == c 93 == c 125 { = d - d 1 ? == d 0 { ^ k } {} } {}
        = k + k 1
    }
    ^ hi
}

// The `;` ending the statement or expression from `lo`, outside brackets.
@ __gpf_semi ( Slice u ) t i lo i hi → i {
    : ~ i d 0
    : ~ i k lo
    ~ < k hi {
        : i c ( slice_byte t k )
        ? | | == c 40 == c 91 == c 123 { = d + d 1 } {}
        ? | | == c 41 == c 93 == c 125 { = d - d 1 } {}
        ? & == d 0 == c 59 { ^ k } {}
        = k + k 1
    }
    ^ hi
}

// Is the word at `k` (an identifier start) exactly `w`?
@ __gpf_word ( Slice u ) t i k i hi s w → b {
    : ( Slice u ) wv ( slice_of_str w )
    : i n ( slice_len [u] wv )
    ? > + k n hi { ^ F } {}
    ? > k 0 { ? ( __gpf_idc ( slice_byte t - k 1 ) ) { ^ F } {} } {}
    ? ( slice_bytes_eq ( slice_window [u] t k n ) wv ) {} { ^ F }
    ? < + k n hi { ? ( __gpf_idc ( slice_byte t + k n ) ) { ^ F } {} } {}
    ^ T
}

// t[lo, hi) with every buffer access v<k>[i] / g<k>[i] a checked load
// LD(v<k>, i), and every store `v<k>[i] = x;` a checked store ST(v<k>, i, x);
@ __gpf_ldst ( Slice u ) t i lo i hi inout String o → v {
    : ~ i k lo
    ~ < k hi {
        : i c ( slice_byte t k )
        : ~ b done F
        ? & | == c 118 == c 103 | == k 0 ! ( __gpf_idc ( slice_byte t - k 1 ) ) {
            : ~ i e + k 1
            ~ & < e hi ( __gpf_dig ( slice_byte t e ) ) { = e + e 1 }
            ? & & > e + k 1 < e hi == ( slice_byte t e ) 91 {
                : i cl ( __gpf_match t e hi )
                : ~ i j + cl 1
                ~ & < j hi == ( slice_byte t j ) 32 { = j + j 1 }
                ? & & < + j 1 hi == ( slice_byte t j ) 61 != ( slice_byte t + j 1 ) 61 {
                    : ~ i r0 + j 1
                    ~ & < r0 hi == ( slice_byte t r0 ) 32 { = r0 + r0 1 }
                    : i sc ( __gpf_semi t r0 hi )
                    ( string_push_str o `ST(` ) ( string_push_window o t k - e k ) ( string_push_str o `, ` )
                    ( __gpf_ldst t + e 1 cl o ) ( string_push_str o `, ` ) ( __gpf_ldst t r0 sc o ) ( string_push_char o 41 )
                    = k sc
                } {
                    ( string_push_str o `LD(` ) ( string_push_window o t k - e k ) ( string_push_str o `, ` )
                    ( __gpf_ldst t + e 1 cl o ) ( string_push_char o 41 )
                    = k + cl 1
                }
                = done T
            } {}
        } {}
        ? done {} {
            ( string_push_char o c )
            = k + k 1
        }
    }
}

// t[lo, hi) with every single-statement if / for / while / else body in
// braces (a checked kernel with SYNC() needs them to see its blocks).
@ __gpf_brace ( Slice u ) t i lo i hi inout String o → v {
    : ~ i k lo
    ~ < k hi {
        : b ctl | | ( __gpf_word t k hi `if` ) ( __gpf_word t k hi `for` ) ( __gpf_word t k hi `while` )
        ? ctl {
            : ~ i p k
            ~ & < p hi != ( slice_byte t p ) 40 { = p + p 1 }
            : i cl ( __gpf_match t p hi )
            ( string_push_window o t k - + cl 1 k )
            = k ( __gpf_body t + cl 1 hi o )
            continue
        } {}
        ? ( __gpf_word t k hi `else` ) {
            ( string_push_str o `else` )
            : ~ i p + k 4
            ~ & < p hi == ( slice_byte t p ) 32 { = p + p 1 }
            ? ( __gpf_word t p hi `if` ) { ( string_push_char o 32 ) = k p continue } {}
            = k ( __gpf_body t + k 4 hi o )
            continue
        } {}
        ( string_push_char o ( slice_byte t k ) )
        = k + k 1
    }
}

// The body statement at `k` braced; where it ends.
@ __gpf_body ( Slice u ) t i k i hi inout String o → i {
    : ~ i p k
    ~ & < p hi | == ( slice_byte t p ) 32 == ( slice_byte t p ) 10 { = p + p 1 }
    ? & < p hi == ( slice_byte t p ) 123 {
        : i cl ( __gpf_match t p hi )
        ( string_push_str o ` {` )
        ( __gpf_brace t + p 1 cl o )
        ( string_push_char o 125 )
        ^ + cl 1
    } {}
    : i sc ( __gpf_semi t p hi )
    ( string_push_str o ` { ` )
    ( __gpf_brace t p + sc 1 o )
    ( string_push_str o ` }` )
    ^ + sc 1
}

// Every kernel of the generated source as a checked kernel: its name, its
// body in the subset, and the node buffers it binds.
@ __gpf_kernels s src → ( Vec GpfKern ) {
    : ~ ( Vec GpfKern ) out ( vec_new [GpfKern] )
    : ( Slice u ) t ( slice_of_str src )
    : i n ( slice_len [u] t )
    : ( Slice u ) pre ( slice_of_str `extern "C" __global__ void ` )
    : i pl ( slice_len [u] pre )
    : ~ i k 0
    ~ < + k pl n {
        ? ( slice_bytes_eq ( slice_window [u] t k pl ) pre ) {} { = k + k 1 continue }
        : i n0 + k pl
        : ~ i p n0
        ~ & < p n != ( slice_byte t p ) 40 { = p + p 1 }
        : ~ String name ( string_new )
        ( string_push_window name t n0 - p n0 )
        : i pc ( __gpf_match t p n )
        : ~ String params ( string_new )
        ( string_push_window params t + p 1 - - pc p 1 )
        : ~ i ob + pc 1
        ~ & < ob n != ( slice_byte t ob ) 123 { = ob + ob 1 }
        : i cb ( __gpf_match t ob n )
        // the body, line by line: table declarations become bindings, the
        // early-return guards an enclosing `if`, CUDA's coordinates ours
        : ~ ( Vec i ) vids ( vec_new [i] )
        : ~ ( Vec i ) gids ( vec_new [i] )
        : ~ String b1 ( string_new )
        : ~ i wraps 0
        : ~ i q + ob 1
        ~ < q cb {
            : ~ i e q
            ~ & < e cb != ( slice_byte t e ) 10 { = e + e 1 }
            : ~ String ln ( string_new )
            ( string_push_window ln t q - e q )
            : s l ( string_data ln )
            : i vt ( nurl_str_find l `(unsigned long long)vt[` )
            : i gt ( nurl_str_find l `(unsigned long long)gt[` )
            ? | >= vt 0 >= gt 0 {
                : i at + ? >= vt 0 vt gt 23
                : ( Slice u ) lv ( slice_of_str l )
                : ~ i m at
                : ~ i id 0
                ~ & < m ( slice_len [u] lv ) ( __gpf_dig ( slice_byte lv m ) ) { = id + * id 10 - ( slice_byte lv m ) 48 = m + m 1 }
                ? >= vt 0 { ( vec_push [i] vids id ) } { ( vec_push [i] gids id ) }
            } {
                ? != 0 ( nurl_str_eq l `    long long s = blockIdx.x;` ) {
                    ( string_push_str b1 `    long long s = bid;\n` )
                } {
                    ? != 0 ( nurl_str_eq l `    if (s >= B) return;` ) {
                        ( string_push_str b1 `    if (s < B) {\n` ) = wraps + wraps 1
                    } {
                        ? != 0 ( nurl_str_eq l `    if (blockIdx.x != 0) return;` ) {
                            ( string_push_str b1 `    if (bid == 0) {\n` ) = wraps + wraps 1
                        } {
                            ( string_push_str b1 l ) ( string_push_char b1 10 )
                        }
                    }
                }
            }
            = q + e 1
        }
        ~ > wraps 0 { ( string_push_str b1 `    }\n` ) = wraps - wraps 1 }
        : ~ String b2 ( _str_replace_all ( string_data b1 ) `blockIdx.x` `bid` )
        = b2 ( _str_replace_all ( string_data b2 ) `threadIdx.x` `tid` )
        = b2 ( _str_replace_all ( string_data b2 ) `blockDim.x` `bdim` )
        = b2 ( _str_replace_all ( string_data b2 ) `gridDim.x` `nblocks` )
        = b2 ( _str_replace_all ( string_data b2 ) `__syncthreads()` `SYNC()` )
        : ~ String b3 ( string_new )
        : ( Slice u ) t2 ( slice_of_str ( string_data b2 ) )
        ( __gpf_ldst t2 0 ( slice_len [u] t2 ) b3 )
        : ~ String b4 ( string_new )
        : ( Slice u ) t3 ( slice_of_str ( string_data b3 ) )
        ( __gpf_brace t3 0 ( slice_len [u] t3 ) b4 )
        : b hasb >= ( nurl_str_find ( string_data params ) `long long B` ) 0
        ( vec_push [GpfKern] out @ GpfKern { name b4 vids gids hasb } )
        = k + cb 1
    }
    ^ out
}

// Launch generated kernel `kname` — recorded into `rs` the first time
// (slot `ri`), replayed after it. `rows` is B.
@ _gpf_run inout GProg pg ( Vec GpfKern ) ks inout ( Vec GkLaunch ) rs inout i ri s kname i rows i nb i blk → b {
    : i at ri
    = ri + ri 1
    ? < at ( vec_len [GkLaunch] rs ) { ^ ( gk_replay ( vec_at [GkLaunch] rs at ) ) } {}
    : ~ i w -1
    : ~ i q 0
    ~ & < q ( vec_len [GpfKern] ks ) < w 0 {
        ? != 0 ( nurl_str_eq ( string_data . ( vec_at [GpfKern] ks q ) name ) kname ) { = w q } {}
        = q + q 1
    }
    ? < w 0 { ( _gp_fail pg `gpfuse: a generated kernel is missing` ) ^ F } {}
    : GpfKern kn ( vec_at [GpfKern] ks w )
    : ~ GkCall c ( gk_call_new )
    : ~ i j 0
    ~ < j ( vec_len [i] . kn vids ) {
        : i id ( _ti . kn vids j )
        : ~ String bn ( string_from `v` )
        ( string_push_int bn id )
        ( gk_call_dev c ( string_data bn ) . ( _gp_node pg id ) val )
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [i] . kn gids ) {
        : i id ( _ti . kn gids j )
        : ~ String bn ( string_from `g` )
        ( string_push_int bn id )
        ( gk_call_dev c ( string_data bn ) . ( _gp_node pg id ) grad )
        = j + j 1
    }
    ? . kn hasb { ( gk_call_i64 c `B` rows ) } {}
    : GkLaunch l ( gk_record_dev . pg kit c kname ( string_data . kn body ) ? < nb 0 ( vec_len [i] . kn gids ) nb blk )
    ? ( gk_launch_ok l ) {} {
        : ~ String why ( string_from `gpfuse kernel ` )
        ( string_push_str why kname ) ( string_push_str why `: ` ) ( string_push_str why ( gk_checked_error c ) )
        ( _gp_fail pg ( string_data why ) )
        ^ F
    }
    : b r ( gk_replay l )
    ( vec_push [GkLaunch] rs l )
    ^ r
}

// Fused backward: one zero-fill launch, the seed, then the reverse walk
// with row-space + param-space kernels standing in for fused segments.
@ _gpfuse_bwd_launches inout GProg pg inout GpPlan pl → b {
    : ~ b r T
    : ~ i ri 0
    // every gradient zeroed — one block per gradient — then the seed
    : ~ i fq 0
    ~ & r < fq ( vec_len [String] . pl fills ) {
        = r ( _gpf_run pg . pl ks . pl brec ri ( string_data ( vec_at [String] . pl fills fq ) ) . pl rows -1 256 )
        = fq + fq 1
    }
    ? r {
        : GpNode lo2 ( _gp_node pg . pg loss )
        : GkBuf lg . lo2 grad
        ? ( gk_buf_ok lg ) {
            : i at ri
            = ri + ri 1
            ? < at ( vec_len [GkLaunch] . pl brec ) { = r ( gk_replay ( vec_at [GkLaunch] . pl brec at ) ) } { = r ( _gp_fill_rec pg . pl brec lg 1.0 ) }
        } {}
    } {}
    : i nseg / ( vec_len [i] . pl segs ) 2
    : ~ i k . pg loss
    ~ & >= k 0 r {
        : ~ i si -1
        : ~ i w 0
        ~ < w nseg {
            ? == ( _ti . pl segs + * w 2 1 ) k {
                : s bn ?? ( vec_get [String] . pl bnames w ) { T x → ( string_data x ) F → `` }
                ? > ( nurl_str_len bn ) 0 { = si w } {}
            } {}
            = w + w 1
        }
        ? >= si 0 {
            : s bn2 ?? ( vec_get [String] . pl bnames si ) { T x → ( string_data x ) F → `` }
            = r ( _gpf_run pg . pl ks . pl brec ri bn2 . pl rows . pl rows 256 )
            : s pn ?? ( vec_get [String] . pl pnames si ) { T x → ( string_data x ) F → `` }
            ? & r > ( nurl_str_len pn ) 0 {
                = r ( _gpf_run pg . pl ks . pl brec ri pn . pl rows ( _ti . pl pgrid si ) 256 )
            } {}
            = k - ( _ti . pl segs * si 2 ) 1
        } {
            : ~ i ssi -1
            : i nser2 / ( vec_len [i] . pl ssegs ) 2
            : ~ i w2 0
            ~ < w2 nser2 {
                ? == ( _ti . pl ssegs + * w2 2 1 ) k {
                    : s sn3 ?? ( vec_get [String] . pl sbnames w2 ) { T x → ( string_data x ) F → `` }
                    ? > ( nurl_str_len sn3 ) 0 { = ssi w2 } {}
                } {}
                = w2 + w2 1
            }
            ? >= ssi 0 {
                : s sb2 ?? ( vec_get [String] . pl sbnames ssi ) { T x → ( string_data x ) F → `` }
                = r ( _gpf_run pg . pl ks . pl brec ri sb2 . pl rows 1 256 )
                = k - ( _ti . pl ssegs * ssi 2 ) 1
            } {
                = r ( _gp_bwd_node pg k )
                = k - k 1
            }
        }
    }
    ^ r
}

@ gpfuse_backward inout GProg pg inout GpPlan pl → b {
    ? & . pg ok . pl ok {} { ^ F }
    ( gk_autosync F )
    : b r ( _gpfuse_bwd_launches pg pl )
    ( gk_autosync T )
    ? r { ^ ( gk_sync . pg kit ) } {}
    ^ F
}

// Fusion pays where kernel LAUNCH LATENCY dominates — the cuda backend.
// The cpu backend has no launch latency and simulates a block's threads
// as fibers, so a barrier-heavy fused kernel only adds swapcontext cost
// there; the per-node path is already the optimal cpu execution. The
// planner still builds (the bit gates run everywhere) — this is the
// production selector.
@ gpfuse_worthwhile inout GProg pg → b {
    ? . pg ok {} { ^ F }
    : GpuKit kit . pg kit
    ^ == 1 ( nurl_str_eq ( gk_backend kit ) `cuda` )
}

// The megakernel episode as ONE CUDA graph: fused forward + fused
// backward + the optimizer, captured once. Per episode the host does
// gput_set_input + gpopt_prepare + gput_episode — the identical driver
// loop as the per-node graph, just with ~5 kernels inside instead of ~40.
@ gpfuse_graph_capture_train inout GProg pg inout GpPlan pl inout GpOpt go → b {
    ? & & . pg ok . pl ok . go ok {} { ^ F }
    ? ( gpu_graph_ok . pg gexec ) { ^ T } {}
    ? ( _gpopt_ensure go pg ) {} { ^ F }
    : GpuKit kit . pg kit
    ? ( gpu_graph_begin ( gk_gpu kit ) ) {} { ^ F }
    ( gk_autosync F )
    : ~ b r ( _gpfuse_fwd_launches pg pl )
    = r & r ( _gpfuse_bwd_launches pg pl )
    = r & r ( _gpopt_launches go pg )
    ( gk_autosync T )
    : GpuGraph exec ( gpu_graph_end ( gk_gpu kit ) )
    ? & r ( gpu_graph_ok exec ) {
        = . pg gexec exec
        ^ T
    } {}
    ^ F
}

// ── serial-space fusion ──────────────────────────────────────────────
// The scalar tail — L2 terms, sum/mean reductions, the loss chain — is a
// string of tiny per-node kernels (gp_reduce already runs single-thread).
// A maximal consecutive run of SERIAL-fusable nodes becomes one
// single-thread kernel with the nodes' exact per-element expressions in
// program order; elements are independent (or serially reduced exactly
// like gp_reduce), so values stay bit-identical. Row segments take
// priority; serial segments claim what is left.

@ _gpf_smax → i { ^ 16384 }

@ _gpf_in_rowseg inout GpPlan pl i k → b {
    : i nseg / ( vec_len [i] . pl segs ) 2
    : ~ i w 0
    ~ < w nseg {
        ? & >= k ( _ti . pl segs * w 2 ) <= k ( _ti . pl segs + * w 2 1 ) { ^ T } {}
        = w + w 1
    }
    ^ F
}

@ _gpf_serial_ok inout GProg pg i k → b {
    : GpNode nd ( _gp_node pg k )
    : i op . nd op
    ? <= op ( gop_const ) { ^ F }
    ? | == op ( gop_sum ) == op ( gop_mean ) { ^ T } {}
    ? > . nd n ( _gpf_smax ) { ^ F }
    ? & >= op ( gop_add ) <= op ( gop_div ) {
        : GpNode na ( _gp_node pg . nd a )
        : GpNode nb ( _gp_node pg . nd b )
        ? & & == . na rows . nd rows == . na cols . nd cols == . na n . nd n {} { ^ F }
        ? == . nb n 1 { ^ T } {}
        ^ & & == . nb rows . nd rows == . nb cols . nd cols == . nb n . nd n
    } {}
    ? & >= op ( gop_neg ) <= op ( gop_sqrt ) { ^ T } {}
    ^ F
}

// v<id>[<ix>] / g<id>[<ix>]
@ _gpf_sel String o i id s ix → v {
    ( _gpf_t o id )
    ( string_push_str o `[` )
    ( string_push_str o ix )
    ( string_push_str o `]` )
}

@ _gpf_sgel String o i id s ix → v {
    ( _gpf_g o id )
    ( string_push_str o `[` )
    ( string_push_str o ix )
    ( string_push_str o `]` )
}

// b-side element with the scalar-[1] broadcast collapsed to [0].
@ _gpf_sinb String o inout GProg pg i inid s ix → v {
    : GpNode nb ( _gp_node pg inid )
    ( _gpf_sel o inid ? == . nb n 1 `0` ix )
}

// Serial forward stages; node values in program order, exact expressions.
@ _gpf_emit_ser_stages inout GProg pg i lo i hi String o ( Vec i ) vids → i {
    : ~ i stages 0
    : ~ i k lo
    ~ <= k hi {
        : GpNode nd ( _gp_node pg k )
        : i op . nd op
        : b _s ( _gpf_seen vids k )
        = stages + stages 1
        ? | == op ( gop_sum ) == op ( gop_mean ) {
            : GpNode na ( _gp_node pg . nd a )
            : b _a ( _gpf_seen vids . nd a )
            // gp_reduce verbatim — serial in thread 0, exact order
            ( string_push_str o `    if (threadIdx.x == 0) { double acc = 0.0;\n      for (long long q = 0; q < ` )
            ( string_push_str o ( nurl_str_int . na n ) )
            ( string_push_str o `; q++) acc = __dadd_rn(acc, ` )
            ( _gpf_sel o . nd a `q` )
            ( string_push_str o `);\n      ` )
            ? == op ( gop_mean ) {
                ( string_push_str o `acc = __ddiv_rn(acc, (double)` )
                ( string_push_str o ( nurl_str_int . na n ) )
                ( string_push_str o `);\n      ` )
            } {}
            ( _gpf_sel o k `0` )
            ( string_push_str o ` = acc; }\n    __syncthreads();\n` )
        } {
            : b _a2 ( _gpf_seen vids . nd a )
            ? >= . nd b 0 { : b _b2 ( _gpf_seen vids . nd b ) } {}
            ( string_push_str o `    for (long long e = threadIdx.x; e < ` )
            ( string_push_str o ( nurl_str_int . nd n ) )
            ( string_push_str o `; e += blockDim.x) ` )
            ( _gpf_sel o k `e` )
            ( string_push_str o ` = ` )
            ( _gpf_sexpr pg k o )
            ( string_push_str o `;\n    __syncthreads();\n` )
        }
        = k + k 1
    }
    ^ stages
}

// The serial per-element expression at flat index e (gp_ew_bc / gp_scal /
// gp_trans forms with the trivial layouts this class permits).
@ _gpf_sexpr inout GProg pg i k String o → v {
    : GpNode nd ( _gp_node pg k )
    : i op . nd op
    ? == op ( gop_add ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `, ` ) ( _gpf_sinb o pg . nd b `e` ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_sub ) { ( string_push_str o `__dsub_rn(` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `, ` ) ( _gpf_sinb o pg . nd b `e` ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_mul ) { ( string_push_str o `__dmul_rn(` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `, ` ) ( _gpf_sinb o pg . nd b `e` ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_div ) { ( string_push_str o `__ddiv_rn(` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `, ` ) ( _gpf_sinb o pg . nd b `e` ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_neg ) { ( string_push_str o `__dsub_rn(0.0, ` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_adds ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `, ` ) ( _gpf_lit o . nd s ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_muls ) { ( string_push_str o `__dmul_rn(` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `, ` ) ( _gpf_lit o . nd s ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_relu ) { ( _gpf_sel o . nd a `e` ) ( string_push_str o ` > 0.0 ? ` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o ` : 0.0` ) ^ v } {}
    ? == op ( gop_sigmoid ) { ( string_push_str o `__ddiv_rn(1.0, __dadd_rn(1.0, exp(__dsub_rn(0.0, ` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `))))` ) ^ v } {}
    ? == op ( gop_tanh ) {
        ( string_push_str o `__ddiv_rn(__dsub_rn(exp(__dmul_rn(2.0, ` )
        ( _gpf_sel o . nd a `e` )
        ( string_push_str o `)), 1.0), __dadd_rn(exp(__dmul_rn(2.0, ` )
        ( _gpf_sel o . nd a `e` )
        ( string_push_str o `)), 1.0))` )
        ^ v
    } {}
    ? == op ( gop_exp ) { ( string_push_str o `exp(` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_log ) { ( string_push_str o `log(` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `)` ) ^ v } {}
    ? == op ( gop_sqrt ) { ( string_push_str o `sqrt(` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `)` ) ^ v } {}
    ( string_push_str o `0.0 /* unreachable */` )
}

// Serial backward stages hi→lo — gp_bw_reduce / gp_bw_unary / accred
// element order, one thread, exact accumulate order per element.
@ _gpf_emit_ser_bwd_stages inout GProg pg i lo i hi String o ( Vec i ) vids ( Vec i ) gids → i {
    : ~ i stages 0
    : ~ i k hi
    ~ >= k lo {
        : GpNode nd ( _gp_node pg k )
        : i op . nd op
        ? == . nd reach 1 {
            ? | == op ( gop_sum ) == op ( gop_mean ) {
                : GpNode na ( _gp_node pg . nd a )
                ? == . na reach 1 {
                    = stages + stages 1
                    : b _g ( _gpf_seen gids k )
                    : b _t ( _gpf_seen gids . nd a )
                    ( string_push_str o `    { double g0 = ` )
                    ( _gpf_sgel o k `0` )
                    ( string_push_str o `;\n      ` )
                    ? == op ( gop_mean ) {
                        ( string_push_str o `g0 = __ddiv_rn(g0, (double)` )
                        ( string_push_str o ( nurl_str_int . na n ) )
                        ( string_push_str o `);\n      ` )
                    } {}
                    ( string_push_str o `for (long long e = threadIdx.x; e < ` )
                    ( string_push_str o ( nurl_str_int . na n ) )
                    ( string_push_str o `; e += blockDim.x) ` )
                    ( _gpf_sgel o . nd a `e` )
                    ( string_push_str o ` = __dadd_rn(` )
                    ( _gpf_sgel o . nd a `e` )
                    ( string_push_str o `, g0); }\n    __syncthreads();\n` )
                } {}
            } {}
            ? & >= op ( gop_add ) <= op ( gop_div ) {
                : GpNode na ( _gp_node pg . nd a )
                : GpNode nb ( _gp_node pg . nd b )
                : b needa == . na reach 1
                : b needb == . nb reach 1
                ? | needa needb {
                    = stages + stages 1
                    : b _g ( _gpf_seen gids k )
                    ? needa {
                        : b _t ( _gpf_seen gids . nd a )
                        ( string_push_str o `    for (long long e = threadIdx.x; e < ` )
                        ( string_push_str o ( nurl_str_int . nd n ) )
                        ( string_push_str o `; e += blockDim.x) ` )
                        ( _gpf_sgel o . nd a `e` )
                        ( string_push_str o ` = __dadd_rn(` )
                        ( _gpf_sgel o . nd a `e` )
                        ( string_push_str o `, __dmul_rn(1.0, ` )
                        ? == op ( gop_add ) { ( _gpf_sgel o k `e` ) } {}
                        ? == op ( gop_sub ) { ( _gpf_sgel o k `e` ) } {}
                        ? == op ( gop_mul ) {
                            : b _v ( _gpf_seen vids . nd b )
                            ( string_push_str o `__dmul_rn(` )
                            ( _gpf_sgel o k `e` )
                            ( string_push_str o `, ` )
                            ( _gpf_sinb o pg . nd b `e` )
                            ( string_push_str o `)` )
                        } {}
                        ? == op ( gop_div ) {
                            : b _v ( _gpf_seen vids . nd b )
                            ( string_push_str o `__ddiv_rn(` )
                            ( _gpf_sgel o k `e` )
                            ( string_push_str o `, ` )
                            ( _gpf_sinb o pg . nd b `e` )
                            ( string_push_str o `)` )
                        } {}
                        ( string_push_str o `));\n    __syncthreads();\n` )
                    } {}
                    ? needb {
                        : b _t2 ( _gpf_seen gids . nd b )
                        : s sg2 ? | == op ( gop_sub ) == op ( gop_div ) `-1.0` `1.0`
                        ? == . nb n 1 {
                            // scalar target: accred's serial odometer
                            ( string_push_str o `    if (threadIdx.x == 0) { double g0 = ` )
                            ( _gpf_sgel o . nd b `0` )
                            ( string_push_str o `;\n      for (long long e = 0; e < ` )
                            ( string_push_str o ( nurl_str_int . nd n ) )
                            ( string_push_str o `; e++) g0 = __dadd_rn(g0, __dmul_rn(` )
                            ( string_push_str o sg2 )
                            ( string_push_str o `, ` )
                            ( _gpf_ser_bsrc pg k o )
                            ( string_push_str o `));\n      ` )
                            ( _gpf_sgel o . nd b `0` )
                            ( string_push_str o ` = g0; }\n    __syncthreads();\n` )
                        } {
                            ( string_push_str o `    for (long long e = threadIdx.x; e < ` )
                            ( string_push_str o ( nurl_str_int . nd n ) )
                            ( string_push_str o `; e += blockDim.x) ` )
                            ( _gpf_sgel o . nd b `e` )
                            ( string_push_str o ` = __dadd_rn(` )
                            ( _gpf_sgel o . nd b `e` )
                            ( string_push_str o `, __dmul_rn(` )
                            ( string_push_str o sg2 )
                            ( string_push_str o `, ` )
                            ( _gpf_ser_bsrc pg k o )
                            ( string_push_str o `));\n    __syncthreads();\n` )
                        }
                    } {}
                } {}
            } {}
            ? & >= op ( gop_neg ) <= op ( gop_sqrt ) {
                : GpNode na ( _gp_node pg . nd a )
                ? == . na reach 1 {
                    = stages + stages 1
                    : b _g ( _gpf_seen gids k )
                    : b _t ( _gpf_seen gids . nd a )
                    ( string_push_str o `    for (long long e = threadIdx.x; e < ` )
                    ( string_push_str o ( nurl_str_int . nd n ) )
                    ( string_push_str o `; e += blockDim.x) { double gi = ` )
                    ( _gpf_sgel o k `e` )
                    ( string_push_str o `; ` )
                    ( _gpf_sgel o . nd a `e` )
                    ( string_push_str o ` = ` )
                    ( _gpf_ser_unary pg k o )
                    ( string_push_str o `; }\n    __syncthreads();\n` )
                } {}
            } {}
        } {}
        = k - k 1
    }
    ^ stages
}

// mul/div/add/sub b-side source element (accred's scr chain, inline).
@ _gpf_ser_bsrc inout GProg pg i k String o → v {
    : GpNode nd ( _gp_node pg k )
    : i op . nd op
    ? == op ( gop_mul ) {
        ( string_push_str o `__dmul_rn(` )
        ( _gpf_sgel o k `e` )
        ( string_push_str o `, ` )
        ( _gpf_sel o . nd a `e` )
        ( string_push_str o `)` )
        ^ v
    } {}
    ? == op ( gop_div ) {
        ( string_push_str o `__ddiv_rn(__dmul_rn(` )
        ( _gpf_sgel o k `e` )
        ( string_push_str o `, ` )
        ( _gpf_sel o k `e` )
        ( string_push_str o `), ` )
        ( _gpf_sinb o pg . nd b `e` )
        ( string_push_str o `)` )
        ^ v
    } {}
    ( _gpf_sgel o k `e` )
}

// gp_bw_unary's accumulate expression with gi bound, serial index e.
@ _gpf_ser_unary inout GProg pg i k String o → v {
    : GpNode nd ( _gp_node pg k )
    : i op . nd op
    ? == op ( gop_neg ) { ( string_push_str o `__dsub_rn(` ) ( _gpf_sgel o . nd a `e` ) ( string_push_str o `, gi)` ) ^ v } {}
    ? == op ( gop_adds ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_sgel o . nd a `e` ) ( string_push_str o `, gi)` ) ^ v } {}
    ? == op ( gop_muls ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_sgel o . nd a `e` ) ( string_push_str o `, __dmul_rn(gi, ` ) ( _gpf_lit o . nd s ) ( string_push_str o `))` ) ^ v } {}
    ? == op ( gop_relu ) { ( _gpf_sel o k `e` ) ( string_push_str o ` > 0.0 ? __dadd_rn(` ) ( _gpf_sgel o . nd a `e` ) ( string_push_str o `, gi) : ` ) ( _gpf_sgel o . nd a `e` ) ^ v } {}
    ? == op ( gop_sigmoid ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_sgel o . nd a `e` ) ( string_push_str o `, __dmul_rn(gi, __dmul_rn(` ) ( _gpf_sel o k `e` ) ( string_push_str o `, __dsub_rn(1.0, ` ) ( _gpf_sel o k `e` ) ( string_push_str o `))))` ) ^ v } {}
    ? == op ( gop_tanh ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_sgel o . nd a `e` ) ( string_push_str o `, __dmul_rn(gi, __dsub_rn(1.0, __dmul_rn(` ) ( _gpf_sel o k `e` ) ( string_push_str o `, ` ) ( _gpf_sel o k `e` ) ( string_push_str o `))))` ) ^ v } {}
    ? == op ( gop_exp ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_sgel o . nd a `e` ) ( string_push_str o `, __dmul_rn(gi, ` ) ( _gpf_sel o k `e` ) ( string_push_str o `))` ) ^ v } {}
    ? == op ( gop_log ) { ( string_push_str o `__dadd_rn(` ) ( _gpf_sgel o . nd a `e` ) ( string_push_str o `, __ddiv_rn(gi, ` ) ( _gpf_sel o . nd a `e` ) ( string_push_str o `))` ) ^ v } {}
    ( string_push_str o `__dadd_rn(` )
    ( _gpf_sgel o . nd a `e` )
    ( string_push_str o `, __ddiv_rn(gi, __dmul_rn(2.0, ` )
    ( _gpf_sel o k `e` )
    ( string_push_str o `)))` )
}

// Assemble the serial fwd kernel (T on success — always has stages).
@ _gpf_emit_ser_seg inout GProg pg i lo i hi s kname String o → b {
    : String body ( string_new )
    : ( Vec i ) vids ( vec_new [i] )
    : i stages ( _gpf_emit_ser_stages pg lo hi body vids )
    ? > stages 0 {} {
        ^ F
    }
    ( string_push_str o `extern "C" __global__ void ` )
    ( string_push_str o kname )
    ( string_push_str o `(const long long* vt, long long B)\n{\n` )
    ( string_push_str o `    if (blockIdx.x != 0) return;\n` )
    : ~ i q 0
    ~ < q ( vec_len [i] vids ) {
        ( _gpf_decl o ( _ti vids q ) T )
        = q + q 1
    }
    ( string_push_str o ( string_data body ) )
    ( string_push_str o `}\n` )
    ^ T
}

// Assemble the serial bwd kernel (F when no reach-1 stages).
@ _gpf_emit_ser_bwd_seg inout GProg pg i lo i hi s kname String o → b {
    : String body ( string_new )
    : ( Vec i ) vids ( vec_new [i] )
    : ( Vec i ) gids ( vec_new [i] )
    : i stages ( _gpf_emit_ser_bwd_stages pg lo hi body vids gids )
    ? > stages 0 {} {
        ^ F
    }
    ( string_push_str o `extern "C" __global__ void ` )
    ( string_push_str o kname )
    ( string_push_str o `(const long long* vt, const long long* gt, long long B)\n{\n` )
    ( string_push_str o `    if (blockIdx.x != 0) return;\n` )
    : ~ i q 0
    ~ < q ( vec_len [i] vids ) {
        ( _gpf_decl o ( _ti vids q ) F )
        = q + q 1
    }
    = q 0
    ~ < q ( vec_len [i] gids ) {
        ( _gpf_gdecl o ( _ti gids q ) )
        = q + q 1
    }
    ( string_push_str o ( string_data body ) )
    ( string_push_str o `}\n` )
    ^ T
}

// ── turnkey session ──────────────────────────────────────────────────
// A consumer that just wants "train this captured program fast" builds a
// session once and drives the same three-call episode loop as the graph
// path — set inputs, prepare the optimizer, run the episode — without
// hand-rolling plan + capture + fallback. When fusion is not worthwhile
// (cpu backend) or the plan is empty, every call transparently forwards
// to the per-node path, so the loop is identical either way.

: GpFuse {
    b active  // T when a worthwhile plan drives the episode
    GpPlan pl
}

// A GpFuse is a handle on its state in an Arc (stdlib/std/arc.nu):
// every copy is the same state, and the last owner releases it.
// The state, for this package's own code.
@ gpfuse_open inout GProg pg inout GpOpt go → GpFuse {
    : ~ b active F
    : ~ GpPlan plan ( _gpfuse_nullplan )
    ? & ( gpfuse_worthwhile pg ) . pg ok {
        : ~ GpPlan live ( gpfuse_plan pg )
        ? . live ok {
            : b _graph ( gpfuse_graph_capture_train pg live go )
            // even without a graph (capture unavailable) the direct fused
            // path still helps — mark active so the episode uses it
            = active T
            = plan live
        } {}
    } {}
    ^ @ GpFuse { active plan }
}

@ _gpfuse_nullplan → GpPlan {
    ^ @ GpPlan { F 0 0 ( vec_new [i] ) ( string_new ) ( vec_new [String] ) ( vec_new [String] )
        ( vec_new [String] ) ( vec_new [i] ) ( vec_new [GpfKern] ) ( vec_new [GkLaunch] ) ( vec_new [GkLaunch] ) ( vec_new [String] ) ( string_new )
        ( vec_new [i] ) ( vec_new [String] ) ( vec_new [String] ) }
}

@ gpfuse_active inout GpFuse s → b {
    ^ . s active
}

// One training episode. With a captured graph this is a single launch;
// with a live plan it is the fused forward + backward + optimizer step;
// otherwise the per-node forward/backward/step. Bit-identical either way.
@ gpfuse_episode inout GpFuse s inout GProg pg inout GpOpt go → b {
    ? & . s active . . s pl ok {} {
        ? ( gput_forward pg ) {} { ^ F }
        ? ( gput_backward pg ) {} { ^ F }
        ^ ( gpopt_step go pg )
    }
    ? ( gpu_graph_ok . pg gexec ) {
        ? ( gpopt_prepare go pg ) {} { ^ F }
        ^ ( gput_episode pg )
    } {}
    ? ( gpfuse_forward pg . s pl ) {} { ^ F }
    ? ( gpfuse_backward pg . s pl ) {} { ^ F }
    ^ ( gpopt_step go pg )
}

// Let go of `s` now rather than at the end of its owner's scope (its plan
// goes with its last owner).
@ gpfuse_close sink GpFuse s → v {}
