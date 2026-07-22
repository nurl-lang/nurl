// grad/emitc.nu — emit a recorded SCALAR tape as CUDA-C source: the
// `__device__ void grad(...)` function swarm-mcp's compute_iterate runs on
// every worker. This closes the loop the keystone plan named: distributed
// backward passes are now DERIVED from the tape, not hand-written CUDA-C.
//
// Scope: every node must be a single-element tensor (shape [1] — scalars;
// g_sum/g_mean of a scalar pass through). The per-example loss is built
// once with placeholder leaves; the emitter walks the tape and prints
//   forward:   double tN = <op mirror>;
//   backward:  double gN = 0.0;  …  gA += …;   (reverse order, seed 1.0)
//   epilogue:  swarm_g_add(g, j, g<param_j>);
// Leaf binding: parameters map to p[j] in registration order; data leaves
// map to caller-supplied C expressions (`v`, `(double)x`, …). Requires-grad
// propagation mirrors grad.nu — const-only branches emit no backward code.
//
// The C forms mirror grad.nu's scalar arithmetic EXPRESSION BY EXPRESSION
// (sigmoid = 1/(1+exp(0-x)), tanh via e2=exp(2x), div's gB via gN*tN/tB…),
// so a host build with -ffp-contract=off reproduces the tape BIT FOR BIT —
// tests/emitc_oracle.sh proves exactly that with gcc.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `grad.nu`
$ `deps/tensor/src/tensor.nu`

@ __ec_t String o i k → v {
    ( string_push_str o `t` )
    ( string_push_str o ( nurl_str_int k ) )
}

@ __ec_g String o i k → v {
    ( string_push_str o `g` )
    ( string_push_str o ( nurl_str_int k ) )
}

@ __ec_f String o f v → v { ( string_push_str o ( nurl_str_float v ) ) }

// The C expression bound to leaf node `k`: `p[j]` for the j-th parameter,
// the caller's expression for a data leaf, else the leaf's recorded VALUE
// as a literal (a frozen scalar const).
@ __ec_leaf * GTape tp i k ( Vec i ) pids ( Vec i ) lids ( Vec s ) lexprs String o → v {
    : ~ i j 0
    ~ < j ( vec_len [i] pids ) {
        ? == ( _ti pids j ) k {
            ( string_push_str o `p[` )
            ( string_push_str o ( nurl_str_int j ) )
            ( string_push_str o `]` )
            ^ v
        } {}
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [i] lids ) {
        ? == ( _ti lids j ) k {
            ( string_push_str o ?? ( vec_get [s] lexprs j ) { T x → x F → `` } )
            ^ v
        } {}
        = j + j 1
    }
    : *Tensor tv # *Tensor ( _g_val tp k )
    ( __ec_f o ( _tf . tv data 0 ) )
}

// Emit the whole device function. `has_v` picks the dataset-bearing
// signature compute_iterate uses. F on any non-scalar node / unknown op.
@ gemit_cuda_grad * GTape tp GVar loss ( Vec i ) pids ( Vec i ) lids ( Vec s ) lexprs b has_v String out → b {
    ? & ( tape_ok tp ) >= . loss id 0 {} { ^ F }
    : i top . loss id
    // scalar check + need/reach sets (grad.nu's rules)
    : ( Vec i ) need ( vec_new [i] )
    : ~ i k 0
    ~ <= k top {
        : *Tensor tv # *Tensor ( _g_val tp k )
        ? == ( vec_len [f] . tv data ) 1 {} { ( vec_free [i] need ) ^ F }
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        : ~ i nv 0
        ? == . nd op ( gop_param ) { = nv 1 } {
            ? & >= . nd a 0 == ( _ti need . nd a ) 1 { = nv 1 } {}
            ? & >= . nd b 0 == ( _ti need . nd b ) 1 { = nv 1 } {}
        }
        // params list decides "param": a grad_param NOT in pids is frozen
        ? == . nd op ( gop_param ) {
            = nv 0
            : ~ i q 0
            ~ < q ( vec_len [i] pids ) {
                ? == ( _ti pids q ) k { = nv 1 } {}
                = q + q 1
            }
        } {}
        ( vec_push [i] need nv )
        = k + k 1
    }
    : ( Vec i ) reach ( vec_new [i] )
    = k 0
    ~ <= k top { ( vec_push [i] reach 0 ) = k + k 1 }
    ( vec_set [i] reach top 1 )
    = k top
    ~ >= k 0 {
        ? == ( _ti reach k ) 1 {
            : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
            ? >= . nd a 0 { ( vec_set [i] reach . nd a 1 ) } {}
            ? >= . nd b 0 { ( vec_set [i] reach . nd b 1 ) } {}
        } {}
        = k - k 1
    }
    ( string_push_str out ? has_v
    `__device__ void grad(long long x, double v, double* g, const double* p) {\n`
    `__device__ void grad(long long x, double* g, const double* p) {\n` )
    // ── forward ──
    = k 0
    : ~ b ok T
    ~ & <= k top ok {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        : i op . nd op
        ( string_push_str out `  double ` )
        ( __ec_t out k )
        ( string_push_str out ` = ` )
        ? <= op ( gop_const ) { ( __ec_leaf tp k pids lids lexprs out ) } {
            : i a . nd a
            : i b2 . nd b
            ? == op ( gop_add ) { ( __ec_t out a ) ( string_push_str out ` + ` ) ( __ec_t out b2 ) } {}
            ? == op ( gop_sub ) { ( __ec_t out a ) ( string_push_str out ` - ` ) ( __ec_t out b2 ) } {}
            ? == op ( gop_mul ) { ( __ec_t out a ) ( string_push_str out ` * ` ) ( __ec_t out b2 ) } {}
            ? == op ( gop_div ) { ( __ec_t out a ) ( string_push_str out ` / ` ) ( __ec_t out b2 ) } {}
            ? == op ( gop_neg ) { ( string_push_str out `0.0 - ` ) ( __ec_t out a ) } {}
            ? == op ( gop_adds ) { ( __ec_t out a ) ( string_push_str out ` + ` ) ( __ec_f out . nd s ) } {}
            ? == op ( gop_muls ) { ( __ec_t out a ) ( string_push_str out ` * ` ) ( __ec_f out . nd s ) } {}
            ? == op ( gop_relu ) {
                ( __ec_t out a ) ( string_push_str out ` > 0.0 ? ` )
                ( __ec_t out a ) ( string_push_str out ` : 0.0` )
            } {}
            ? == op ( gop_sigmoid ) {
                ( string_push_str out `1.0 / (1.0 + exp(0.0 - ` )
                ( __ec_t out a ) ( string_push_str out `))` )
            } {}
            ? == op ( gop_tanh ) {
                // two-statement form mirroring grad.nu: e2 first
                ( string_push_str out `0.0; { double e2 = exp(2.0 * ` )
                ( __ec_t out a )
                ( string_push_str out `); ` )
                ( __ec_t out k )
                ( string_push_str out ` = (e2 - 1.0) / (e2 + 1.0); }` )
            } {}
            ? == op ( gop_exp ) { ( string_push_str out `exp(` ) ( __ec_t out a ) ( string_push_str out `)` ) } {}
            ? == op ( gop_log ) { ( string_push_str out `log(` ) ( __ec_t out a ) ( string_push_str out `)` ) } {}
            ? == op ( gop_sqrt ) { ( string_push_str out `sqrt(` ) ( __ec_t out a ) ( string_push_str out `)` ) } {}
            ? | == op ( gop_sum ) == op ( gop_mean ) { ( __ec_t out a ) } {}
            // matmul/bmm/shape ops have no scalar mirror — refuse
            ? > op ( gop_mean ) { = ok F } {}
        }
        ( string_push_str out `;\n` )
        = k + k 1
    }
    ? ok {} { ( vec_free [i] need ) ( vec_free [i] reach ) ^ F }
    // ── backward ──
    = k 0
    ~ <= k top {
        ? & == ( _ti need k ) 1 == ( _ti reach k ) 1 {
            ( string_push_str out `  double ` )
            ( __ec_g out k )
            ( string_push_str out ? == k top ` = 1.0;\n` ` = 0.0;\n` )
        } {}
        = k + k 1
    }
    = k top
    ~ >= k 0 {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        : i op . nd op
        ? & & == ( _ti need k ) 1 == ( _ti reach k ) 1 > op ( gop_const ) {
            : i a . nd a
            : i b2 . nd b
            : b na & >= a 0 == ( _ti need a ) 1
            : b nb & >= b2 0 == ( _ti need b2 ) 1
            ? & == op ( gop_add ) na { ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k ) ( string_push_str out `;\n` ) } {}
            ? & == op ( gop_add ) nb { ( string_push_str out `  ` ) ( __ec_g out b2 ) ( string_push_str out ` += ` ) ( __ec_g out k ) ( string_push_str out `;\n` ) } {}
            ? & == op ( gop_sub ) na { ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k ) ( string_push_str out `;\n` ) } {}
            ? & == op ( gop_sub ) nb { ( string_push_str out `  ` ) ( __ec_g out b2 ) ( string_push_str out ` -= ` ) ( __ec_g out k ) ( string_push_str out `;\n` ) } {}
            ? & == op ( gop_mul ) na {
                ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k )
                ( string_push_str out ` * ` ) ( __ec_t out b2 ) ( string_push_str out `;\n` )
            } {}
            ? & == op ( gop_mul ) nb {
                ( string_push_str out `  ` ) ( __ec_g out b2 ) ( string_push_str out ` += ` ) ( __ec_g out k )
                ( string_push_str out ` * ` ) ( __ec_t out a ) ( string_push_str out `;\n` )
            } {}
            ? & == op ( gop_div ) na {
                ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k )
                ( string_push_str out ` / ` ) ( __ec_t out b2 ) ( string_push_str out `;\n` )
            } {}
            ? & == op ( gop_div ) nb {
                ( string_push_str out `  ` ) ( __ec_g out b2 ) ( string_push_str out ` -= ` ) ( __ec_g out k )
                ( string_push_str out ` * ` ) ( __ec_t out k ) ( string_push_str out ` / ` )
                ( __ec_t out b2 ) ( string_push_str out `;\n` )
            } {}
            ? & == op ( gop_neg ) na { ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` -= ` ) ( __ec_g out k ) ( string_push_str out `;\n` ) } {}
            ? & == op ( gop_adds ) na { ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k ) ( string_push_str out `;\n` ) } {}
            ? & == op ( gop_muls ) na {
                ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k )
                ( string_push_str out ` * ` ) ( __ec_f out . nd s ) ( string_push_str out `;\n` )
            } {}
            ? & == op ( gop_relu ) na {
                ( string_push_str out `  if (` ) ( __ec_t out k ) ( string_push_str out ` > 0.0) ` )
                ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k ) ( string_push_str out `;\n` )
            } {}
            ? & == op ( gop_sigmoid ) na {
                ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k )
                ( string_push_str out ` * (` ) ( __ec_t out k ) ( string_push_str out ` * (1.0 - ` )
                ( __ec_t out k ) ( string_push_str out `));\n` )
            } {}
            ? & == op ( gop_tanh ) na {
                ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k )
                ( string_push_str out ` * (1.0 - ` ) ( __ec_t out k ) ( string_push_str out ` * ` )
                ( __ec_t out k ) ( string_push_str out `);\n` )
            } {}
            ? & == op ( gop_exp ) na {
                ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k )
                ( string_push_str out ` * ` ) ( __ec_t out k ) ( string_push_str out `;\n` )
            } {}
            ? & == op ( gop_log ) na {
                ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k )
                ( string_push_str out ` / ` ) ( __ec_t out a ) ( string_push_str out `;\n` )
            } {}
            ? & == op ( gop_sqrt ) na {
                ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k )
                ( string_push_str out ` / (2.0 * ` ) ( __ec_t out k ) ( string_push_str out `);\n` )
            } {}
            ? & | == op ( gop_sum ) == op ( gop_mean ) na {
                ( string_push_str out `  ` ) ( __ec_g out a ) ( string_push_str out ` += ` ) ( __ec_g out k ) ( string_push_str out `;\n` )
            } {}
        } {}
        = k - k 1
    }
    // ── scatter into the K-vector ──
    : ~ i j 0
    ~ < j ( vec_len [i] pids ) {
        : i pk ( _ti pids j )
        ( string_push_str out `  swarm_g_add(g, ` )
        ( string_push_str out ( nurl_str_int j ) )
        ( string_push_str out `, ` )
        ? & == ( _ti need pk ) 1 == ( _ti reach pk ) 1 { ( __ec_g out pk ) } { ( string_push_str out `0.0` ) }
        ( string_push_str out `);\n` )
        = j + j 1
    }
    ( string_push_str out `}\n` )
    ( vec_free [i] need )
    ( vec_free [i] reach )
    ^ T
}
