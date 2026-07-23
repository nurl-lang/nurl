// grad — reverse-mode automatic differentiation over `tensor`.
//
// Define-by-run: every g_* op computes its value EAGERLY through the tensor
// package and appends one node to a flat TAPE. `backward(loss)` walks the
// tape once in reverse — node inputs always have smaller indices, so reverse
// index order IS topological order — accumulating dL/dx into a gradient slot
// per node. Fan-out (one value used twice) sums naturally.
//
// Ownership: the tape is a SINGLE-OWNER ARENA. It owns every value tensor
// and every gradient tensor; `grad_param`/`grad_const` COPY the caller's
// tensor in, `gvar_value`/`grad_of` hand out BORROWS (aliased Tensor views —
// never free them, invalid after tape_free / tape_reset_to), and one
// `tape_free` releases everything. No per-node ownership, no per-node
// closures — a `( Vec GNode )` of {op, a, b, scalar} plus two parallel
// pointer vecs. This keeps the hot loop free of NURL's closure-capture
// hazards and gives a deterministic reverse order for free.
//
// The minibatch pattern: register parameters once, take `tape_mark`, then per
// batch build the episode's graph, `backward`, step the optimizer, and
// `tape_reset_to(mark)` — parameters (and their Adam state, which lives in
// the optimizer) survive, intermediates are freed, the arena keeps its
// capacity.
//
// M1 scope (CPU): elementwise ops + all-axes reductions. Binary ops require
// EQUAL shapes (broadcast backward is M2, with its own oracle); scalar
// variants g_adds/g_muls cover the mixed case. A shape mismatch POISONS the
// tape (tape_ok → F, ops keep returning without touching memory) rather than
// half-computing.
//
// Verification: tests/grad_test.nu checks every backward rule two independent
// ways — central finite differences and hand-derived analytic identities
// (e.g. d/dx Σx² = 2x, exact to the bit).

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/tensor/src/ops.nu`

// ── op codes ──────────────────────────────────────────────────────────
@ gop_param → i { ^ 0 }

@ gop_const → i { ^ 1 }

@ gop_add → i { ^ 2 }

@ gop_sub → i { ^ 3 }

@ gop_mul → i { ^ 4 }

@ gop_div → i { ^ 5 }

@ gop_neg → i { ^ 6 }

@ gop_adds → i { ^ 7 }

@ gop_muls → i { ^ 8 }

@ gop_relu → i { ^ 9 }

@ gop_sigmoid → i { ^ 10 }

@ gop_tanh → i { ^ 11 }

@ gop_exp → i { ^ 12 }

@ gop_log → i { ^ 13 }

@ gop_sqrt → i { ^ 14 }

@ gop_sum → i { ^ 15 }

@ gop_mean → i { ^ 16 }

@ gop_matmul → i { ^ 17 }

@ gop_bmm → i { ^ 18 }

@ gop_transpose → i { ^ 19 }

@ gop_reshape → i { ^ 20 }

@ gop_softmax → i { ^ 21 }

@ gop_slice → i { ^ 22 }

@ gop_concat → i { ^ 23 }

// One tape node: the op, its input node ids (-1 = none), a scalar operand.
: GNode {
    i op
    i a
    i b
    f s
}

// A variable on the tape — an opaque node handle.
: GVar {
    i id
}

: GTape {
    i ok  // 1 healthy · 0 poisoned (shape mismatch etc.)
    ( Vec GNode ) nodes
    ( Vec s ) vals  // *Tensor per node (tape-owned)
    ( Vec s ) grads  // *Tensor per node, 0 until backward touches it
    ( Vec s ) aux  // *GAux per node, 0 for ops that need none (slice starts)
}

// Per-node auxiliary payload (only g_slice uses one today).
: GAux {
    ( Vec i ) starts
}

// ── construction / lifecycle ─────────────────────────────────────────

@ tape_new → *GTape {
    : *GTape tp # *GTape ( nurl_alloc Z GTape )
    = . tp ok 1
    = . tp nodes ( vec_new [GNode] )
    = . tp vals ( vec_new [s] )
    = . tp grads ( vec_new [s] )
    = . tp aux ( vec_new [s] )
    ^ tp
}

@ _g_tfree s pp → v {
    ? != # i pp 0 {
        : *Tensor t # *Tensor pp
        ( vec_free [i] . t shape )
        ( vec_free [f] . t data )
        ( nurl_free pp )
    } {}
}

@ _g_auxfree s pp → v {
    ? != # i pp 0 {
        : *GAux a # *GAux pp
        ( vec_free [i] . a starts )
        ( nurl_free pp )
    } {}
}

@ tape_free * GTape tp → v {
    : i n ( vec_len [s] . tp vals )
    : ~ i k 0
    ~ < k n {
        ( _g_tfree ?? ( vec_get [s] . tp vals k ) { T x → x F → # s 0 } )
        ( _g_tfree ?? ( vec_get [s] . tp grads k ) { T x → x F → # s 0 } )
        ( _g_auxfree ?? ( vec_get [s] . tp aux k ) { T x → x F → # s 0 } )
        = k + k 1
    }
    ( vec_free [s] . tp vals )
    ( vec_free [s] . tp grads )
    ( vec_free [s] . tp aux )
    ( vec_free [GNode] . tp nodes )
    ( nurl_free # s tp )
}

@ tape_ok * GTape tp → b { ^ == . tp ok 1 }

// Free the host VALUE tensors of every const (gop_const) node — the frozen
// base weights and the input consts. After a device capture (gput_capture)
// has uploaded them, nothing on the host reads them again: device replay
// reads device buffers, param sync-back touches only gop_param nodes, and
// gput_set_input uploads freshly-recomputed rows straight to the device.
// So this reclaims the single largest host allocation in a finetune (the
// base weights, held f64) with no effect on device training.
//
// ONLY call it after a successful device capture: the CPU tape can no longer
// forward/backward once its const values are gone. Freeing is null-safe —
// tape_free / tape_reset_to re-read through the same guarded idiom.
@ tape_drop_consts * GTape tp → v {
    : i n ( vec_len [GNode] . tp nodes )
    : ~ i k 0
    ~ < k n {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        ? == . nd op ( gop_const ) {
            ( _g_tfree ?? ( vec_get [s] . tp vals k ) { T x → x F → # s 0 } )
            ( vec_set [s] . tp vals k # s 0 )
        } {}
        = k + k 1
    }
}

@ tape_len * GTape tp → i { ^ ( vec_len [GNode] . tp nodes ) }

// Watermark for tape_reset_to: everything appended after `mark` is dropped.
@ tape_mark * GTape tp → i { ^ ( vec_len [GNode] . tp nodes ) }

// Drop every node at id >= mark (freeing its tensors) and ZERO the gradients
// of what remains — a fresh episode over the surviving parameters. The vecs
// keep their capacity, so a minibatch loop does not re-malloc the arena.
@ tape_reset_to * GTape tp i mark → v {
    : i n ( vec_len [GNode] . tp nodes )
    : ~ i k mark
    ~ < k n {
        ( _g_tfree ?? ( vec_get [s] . tp vals k ) { T x → x F → # s 0 } )
        ( _g_tfree ?? ( vec_get [s] . tp grads k ) { T x → x F → # s 0 } )
        ( _g_auxfree ?? ( vec_get [s] . tp aux k ) { T x → x F → # s 0 } )
        = k + k 1
    }
    : b _t1 ( vec_set_len [GNode] . tp nodes mark )
    : b _t2 ( vec_set_len [s] . tp vals mark )
    : b _t3 ( vec_set_len [s] . tp grads mark )
    : b _t4 ( vec_set_len [s] . tp aux mark )
    // zero the surviving grads in place (keep their buffers)
    = k 0
    ~ < k mark {
        : s gp ?? ( vec_get [s] . tp grads k ) { T x → x F → # s 0 }
        ? != # i gp 0 {
            : *Tensor g # *Tensor gp
            : i gn ( vec_len [f] . g data )
            : ~ i j 0
            ~ < j gn { ( vec_set [f] . g data j 0.0 ) = j + j 1 }
        } {}
        = k + k 1
    }
    = . tp ok 1
}

// ── internals ─────────────────────────────────────────────────────────

// Move a Tensor VALUE into a fresh heap cell the tape owns. The value's Vec
// handles alias into the cell — the caller must NOT free the value after.
@ _g_heap Tensor t → s {
    : *Tensor p # *Tensor ( nurl_alloc Z Tensor )
    = . p dtype . t dtype
    = . p shape . t shape
    = . p data . t data
    ^ # s p
}

@ _g_val * GTape tp i id → s {
    ^ ?? ( vec_get [s] . tp vals id ) { T x → x F → # s 0 }
}

@ _g_grad_ptr * GTape tp i id → s {
    ^ ?? ( vec_get [s] . tp grads id ) { T x → x F → # s 0 }
}

@ _g_poison * GTape tp s why → GVar {
    ? == . tp ok 1 {
        ( nurl_eprint `grad: tape poisoned: ` )
        ( nurl_eprintln why )
    } {}
    = . tp ok 0
    ^ @ GVar { -1 }
}

// Append a node whose value is `val` (ownership moves to the tape).
@ _g_push * GTape tp i op i a i b f sc Tensor val → GVar {
    : i id ( vec_len [GNode] . tp nodes )
    ( vec_push [GNode] . tp nodes @ GNode { op a b sc } )
    ( vec_push [s] . tp vals ( _g_heap val ) )
    ( vec_push [s] . tp grads # s 0 )
    ( vec_push [s] . tp aux # s 0 )
    ^ @ GVar { id }
}

// Equal-shape check for M1 binops.
@ _g_same_shape s pa s pb → b {
    : *Tensor a # *Tensor pa
    : *Tensor b # *Tensor pb
    : i n ( vec_len [i] . a shape )
    ? != n ( vec_len [i] . b shape ) { ^ F } {}
    : ~ i k 0
    ~ < k n {
        ? != ( _ti . a shape k ) ( _ti . b shape k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// ── leaves ────────────────────────────────────────────────────────────

// Register a PARAMETER (requires-grad leaf). The tensor is COPIED in; the
// live, optimizer-updated copy is the tape's (read it via gvar_value).
@ grad_param * GTape tp Tensor w → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ^ ( _g_push tp ( gop_param ) -1 -1 0.0 ( tensor_clone w ) )
}

// Register a CONSTANT (no gradient flows into it).
@ grad_const * GTape tp Tensor c → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ^ ( _g_push tp ( gop_const ) -1 -1 0.0 ( tensor_clone c ) )
}

// ── borrows out ──────────────────────────────────────────────────────

// The node's value as a BORROWED Tensor view (do not free; invalid after
// tape_free / a reset past this node).
@ gvar_value * GTape tp GVar v → Tensor {
    : *Tensor p # *Tensor ( _g_val tp . v id )
    ^ @ Tensor { . p dtype . p shape . p data }
}

// The accumulated gradient as a BORROWED Tensor view. Allocates a zero
// gradient on first touch so the borrow is always valid.
@ grad_of * GTape tp GVar v → Tensor {
    ( _g_ensure_grad tp . v id )
    : *Tensor p # *Tensor ( _g_grad_ptr tp . v id )
    ^ @ Tensor { . p dtype . p shape . p data }
}

// First element of the node's value — the scalar-loss readout.
@ g_scalar * GTape tp GVar v → f {
    : *Tensor p # *Tensor ( _g_val tp . v id )
    ^ ( _tf . p data 0 )
}

// ── ops: binary (equal shapes) ───────────────────────────────────────

// A borrowed Tensor view of a tape value (alias — never free).
@ _g_view s pp → Tensor {
    : *Tensor p # *Tensor pp
    ^ @ Tensor { . p dtype . p shape . p data }
}

@ _g_binop * GTape tp GVar a GVar b i op → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? & >= . a id 0 >= . b id 0 {} { ^ ( _g_poison tp `binop on a poisoned input` ) }
    : s pa ( _g_val tp . a id )
    : s pb ( _g_val tp . b id )
    ? ( _g_same_shape pa pb ) {} {
        // shapes differ → numpy broadcast through the tensor package
        : Tensor va ( _g_view pa )
        : Tensor vb ( _g_view pb )
        : ~ ? Tensor r @ ?Tensor { F }
        ? == op ( gop_add ) { = r ( tensor_add va vb ) } {}
        ? == op ( gop_sub ) { = r ( tensor_sub va vb ) } {}
        ? == op ( gop_mul ) { = r ( tensor_mul va vb ) } {}
        ? == op ( gop_div ) { = r ( tensor_div va vb ) } {}
        ?? r {
            T out → { ^ ( _g_push tp op . a id . b id 0.0 out ) }
            F → { ^ ( _g_poison tp `binop shapes are not broadcast-compatible` ) }
        }
    }
    : *Tensor ta # *Tensor pa
    : *Tensor tb # *Tensor pb
    : i n ( vec_len [f] . ta data )
    : ( Vec f ) out ( vec_with_cap [f] n )
    : ~ i k 0
    ? == op ( gop_add ) {
        ~ < k n { ( vec_push [f] out + ( _tf . ta data k ) ( _tf . tb data k ) ) = k + k 1 }
    } {
        ? == op ( gop_sub ) {
            ~ < k n { ( vec_push [f] out - ( _tf . ta data k ) ( _tf . tb data k ) ) = k + k 1 }
        } {
            ? == op ( gop_mul ) {
                ~ < k n { ( vec_push [f] out * ( _tf . ta data k ) ( _tf . tb data k ) ) = k + k 1 }
            } {
                ~ < k n { ( vec_push [f] out / ( _tf . ta data k ) ( _tf . tb data k ) ) = k + k 1 }
            }
        }
    }
    : ( Vec i ) shp ( vec_clone [i] . ta shape )
    : Tensor val @ Tensor { . ta dtype shp out }
    ^ ( _g_push tp op . a id . b id 0.0 val )
}

@ g_add * GTape tp GVar a GVar b → GVar { ^ ( _g_binop tp a b ( gop_add ) ) }

@ g_sub * GTape tp GVar a GVar b → GVar { ^ ( _g_binop tp a b ( gop_sub ) ) }

@ g_mul * GTape tp GVar a GVar b → GVar { ^ ( _g_binop tp a b ( gop_mul ) ) }

@ g_div * GTape tp GVar a GVar b → GVar { ^ ( _g_binop tp a b ( gop_div ) ) }

// ── ops: unary / scalar ──────────────────────────────────────────────

@ _g_unary * GTape tp GVar a i op f sc → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? >= . a id 0 {} { ^ ( _g_poison tp `unary on a poisoned input` ) }
    : *Tensor ta # *Tensor ( _g_val tp . a id )
    : i n ( vec_len [f] . ta data )
    : ( Vec f ) out ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        : f x ( _tf . ta data k )
        : ~ f y 0.0
        ? == op ( gop_neg ) { = y - 0.0 x } {}
        ? == op ( gop_adds ) { = y + x sc } {}
        ? == op ( gop_muls ) { = y * x sc } {}
        ? == op ( gop_relu ) { = y ? > x 0.0 x 0.0 } {}
        // sigmoid/tanh/exp/log/sqrt mirror tensor's __umap formulas exactly,
        // so a grad forward is bit-identical to the tensor op it shadows.
        ? == op ( gop_sigmoid ) { = y / 1.0 + 1.0 ( float_exp - 0.0 x ) } {}
        ? == op ( gop_tanh ) {
            : f e2 ( float_exp * 2.0 x )
            = y / - e2 1.0 + e2 1.0
        } {}
        ? == op ( gop_exp ) { = y ( float_exp x ) } {}
        ? == op ( gop_log ) { = y ( float_log x ) } {}
        ? == op ( gop_sqrt ) { = y ( float_sqrt x ) } {}
        ( vec_push [f] out y )
        = k + k 1
    }
    : ( Vec i ) shp ( vec_clone [i] . ta shape )
    : Tensor val @ Tensor { . ta dtype shp out }
    ^ ( _g_push tp op . a id -1 sc val )
}

@ g_neg * GTape tp GVar a → GVar { ^ ( _g_unary tp a ( gop_neg ) 0.0 ) }

@ g_adds * GTape tp GVar a f sc → GVar { ^ ( _g_unary tp a ( gop_adds ) sc ) }

@ g_muls * GTape tp GVar a f sc → GVar { ^ ( _g_unary tp a ( gop_muls ) sc ) }

@ g_relu * GTape tp GVar a → GVar { ^ ( _g_unary tp a ( gop_relu ) 0.0 ) }

@ g_sigmoid * GTape tp GVar a → GVar { ^ ( _g_unary tp a ( gop_sigmoid ) 0.0 ) }

@ g_tanh * GTape tp GVar a → GVar { ^ ( _g_unary tp a ( gop_tanh ) 0.0 ) }

@ g_exp * GTape tp GVar a → GVar { ^ ( _g_unary tp a ( gop_exp ) 0.0 ) }

@ g_log * GTape tp GVar a → GVar { ^ ( _g_unary tp a ( gop_log ) 0.0 ) }

@ g_sqrt * GTape tp GVar a → GVar { ^ ( _g_unary tp a ( gop_sqrt ) 0.0 ) }

// ── ops: all-axes reductions (result shape [1]) ─────────────────────

@ _g_reduce * GTape tp GVar a i op → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? >= . a id 0 {} { ^ ( _g_poison tp `reduce on a poisoned input` ) }
    : *Tensor ta # *Tensor ( _g_val tp . a id )
    : i n ( vec_len [f] . ta data )
    : ~ f acc 0.0
    : ~ i k 0
    ~ < k n { = acc + acc ( _tf . ta data k ) = k + k 1 }
    ? == op ( gop_mean ) { = acc / acc # f n } {}
    : ( Vec i ) shp ( vec_new [i] )
    ( vec_push [i] shp 1 )
    : ( Vec f ) out ( vec_new [f] )
    ( vec_push [f] out acc )
    : Tensor val @ Tensor { . ta dtype shp out }
    ^ ( _g_push tp op . a id -1 0.0 val )
}

@ g_sum * GTape tp GVar a → GVar { ^ ( _g_reduce tp a ( gop_sum ) ) }

@ g_mean * GTape tp GVar a → GVar { ^ ( _g_reduce tp a ( gop_mean ) ) }

// Mean squared error as a composite: mean((y − t)²). Exercises fan-out-free
// chaining; the FD harness covers it end to end.
@ g_mse * GTape tp GVar y GVar t → GVar {
    : GVar d ( g_sub tp y t )
    : GVar d2 ( g_mul tp d d )
    ^ ( g_mean tp d2 )
}

// ── ops: linear algebra / shape (M2) ────────────────────────────────
// Forwards go THROUGH the tensor package (borrowed views in, owned tensor
// out), so grad's results are the tensor package's results — including its
// GPU matmul path and any future backend work.

@ g_matmul * GTape tp GVar a GVar b → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? & >= . a id 0 >= . b id 0 {} { ^ ( _g_poison tp `matmul on a poisoned input` ) }
    ?? ( tensor_matmul ( _g_view ( _g_val tp . a id ) ) ( _g_view ( _g_val tp . b id ) ) ) {
        T out → { ^ ( _g_push tp ( gop_matmul ) . a id . b id 0.0 out ) }
        F → { ^ ( _g_poison tp `matmul shape mismatch (needs [m,k]x[k,n])` ) }
    }
}

@ g_bmm * GTape tp GVar a GVar b → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? & >= . a id 0 >= . b id 0 {} { ^ ( _g_poison tp `bmm on a poisoned input` ) }
    ?? ( tensor_bmm ( _g_view ( _g_val tp . a id ) ) ( _g_view ( _g_val tp . b id ) ) ) {
        T out → { ^ ( _g_push tp ( gop_bmm ) . a id . b id 0.0 out ) }
        F → { ^ ( _g_poison tp `bmm shape mismatch (needs [B,m,k]x[B,k,n])` ) }
    }
}

@ g_transpose * GTape tp GVar a → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? >= . a id 0 {} { ^ ( _g_poison tp `transpose on a poisoned input` ) }
    ?? ( tensor_transpose ( _g_view ( _g_val tp . a id ) ) ) {
        T out → { ^ ( _g_push tp ( gop_transpose ) . a id -1 0.0 out ) }
        F → { ^ ( _g_poison tp `transpose needs a 2-D input` ) }
    }
}

// `shape` is borrowed (copied here; tensor_reshape adopts the copy).
@ g_reshape * GTape tp GVar a ( Vec i ) shape → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? >= . a id 0 {} { ^ ( _g_poison tp `reshape on a poisoned input` ) }
    ?? ( tensor_reshape ( _g_view ( _g_val tp . a id ) ) ( vec_clone [i] shape ) ) {
        T out → { ^ ( _g_push tp ( gop_reshape ) . a id -1 0.0 out ) }
        F → { ^ ( _g_poison tp `reshape element count mismatch` ) }
    }
}

@ g_softmax * GTape tp GVar a i axis → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? >= . a id 0 {} { ^ ( _g_poison tp `softmax on a poisoned input` ) }
    : Tensor out ( tensor_softmax ( _g_view ( _g_val tp . a id ) ) axis )
    ^ ( _g_push tp ( gop_softmax ) . a id -1 # f axis out )
}

// starts/stops are borrowed; starts is retained (aux) for the backward scatter.
@ g_slice * GTape tp GVar a ( Vec i ) starts ( Vec i ) stops → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? >= . a id 0 {} { ^ ( _g_poison tp `slice on a poisoned input` ) }
    ?? ( tensor_slice ( _g_view ( _g_val tp . a id ) ) starts stops ) {
        T out → {
            : GVar v ( _g_push tp ( gop_slice ) . a id -1 0.0 out )
            : *GAux ax # *GAux ( nurl_alloc Z GAux )
            = . ax starts ( vec_clone [i] starts )
            ( vec_set [s] . tp aux . v id # s ax )
            ^ v
        }
        F → { ^ ( _g_poison tp `slice window out of range` ) }
    }
}

@ g_concat * GTape tp GVar a GVar b i axis → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? & >= . a id 0 >= . b id 0 {} { ^ ( _g_poison tp `concat on a poisoned input` ) }
    ?? ( tensor_concat2 ( _g_view ( _g_val tp . a id ) ) ( _g_view ( _g_val tp . b id ) ) axis ) {
        T out → { ^ ( _g_push tp ( gop_concat ) . a id . b id # f axis out ) }
        F → { ^ ( _g_poison tp `concat shapes differ off-axis` ) }
    }
}

// ── backward ─────────────────────────────────────────────────────────

// Accumulate an out-shaped contribution `c` into node `dst`'s gradient,
// summing over broadcast axes (numpy alignment: trailing dims line up, a
// size-1 or missing dst dim receives the sum over that out axis). sgn is
// +1/-1 (sub/div's second input negates). Row-major walk of `c` — one
// documented, deterministic accumulation order.
@ _g_acc_reduce * GTape tp i dst Tensor c f sgn → v {
    ( _g_ensure_grad tp dst )
    : *Tensor gd # *Tensor ( _g_grad_ptr tp dst )
    : i nd ( vec_len [i] . c shape )
    : ( Vec i ) cst ( _t_strides . c shape )
    : ( Vec i ) eff ( _t_eff_strides . gd shape nd )
    : i total ( vec_len [f] . c data )
    : ~ i lin 0
    ~ < lin total {
        : ~ i rem lin
        : ~ i off 0
        : ~ i d 0
        ~ < d nd {
            : i st ( _ti cst d )
            : i ix / rem st
            = rem % rem st
            = off + off * ix ( _ti eff d )
            = d + d 1
        }
        ( vec_set [f] . gd data off + ( _tf . gd data off ) * sgn ( _tf . c data lin ) )
        = lin + lin 1
    }
    ( vec_free [i] cst )
    ( vec_free [i] eff )
}

// Allocate node id's gradient as zeros (same shape as its value) if absent.
@ _g_ensure_grad * GTape tp i id → v {
    : s gp ( _g_grad_ptr tp id )
    ? != # i gp 0 { ^ v } {}
    : *Tensor vp # *Tensor ( _g_val tp id )
    : i n ( vec_len [f] . vp data )
    : ( Vec f ) z ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] z 0.0 ) = k + k 1 }
    : ( Vec i ) shp ( vec_clone [i] . vp shape )
    : *Tensor g # *Tensor ( nurl_alloc Z Tensor )
    = . g dtype . vp dtype
    = . g shape shp
    = . g data z
    ( vec_set [s] . tp grads id # s g )
}

// dL/d(node) of `loss` seeds to ones; every earlier node receives the sum of
// its consumers' contributions. Returns F on a poisoned/invalid tape.
@ backward * GTape tp GVar loss → b {
    ? == . tp ok 1 {} { ^ F }
    ? >= . loss id 0 {} { ^ F }
    : i top . loss id
    // requires-grad propagation (PyTorch's rule): a node NEEDS a gradient
    // only if a parameter lies in its ancestor cone. Gradients are neither
    // computed nor stored anywhere else — a frozen-const branch (a LoRA
    // base weight, an input batch) costs nothing in the sweep, and its
    // grad_of stays a zero tensor exactly as before.
    : ( Vec i ) need ( vec_new [i] )
    : ~ i q2 0
    ~ <= q2 top {
        : GNode nq ?? ( vec_get [GNode] . tp nodes q2 ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        : ~ i nv 0
        ? == . nq op ( gop_param ) { = nv 1 } {
            ? & >= . nq a 0 == ( _ti need . nq a ) 1 { = nv 1 } {}
            ? & >= . nq b 0 == ( _ti need . nq b ) 1 { = nv 1 } {}
        }
        ( vec_push [i] need nv )
        = q2 + q2 1
    }
    ( _g_ensure_grad tp top )
    : *Tensor gl # *Tensor ( _g_grad_ptr tp top )
    : i ln ( vec_len [f] . gl data )
    : ~ i q 0
    ~ < q ln { ( vec_set [f] . gl data q 1.0 ) = q + q 1 }
    : ~ i k top
    ~ >= k 0 {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        : s gp ( _g_grad_ptr tp k )
        ? & & != # i gp 0 > . nd op ( gop_const ) == ( _ti need k ) 1 {
            : *Tensor g # *Tensor gp
            : *Tensor yv # *Tensor ( _g_val tp k )
            : i n ( vec_len [f] . g data )
            : i op . nd op
            : i ia . nd a
            : i ib . nd b
            : b needa & >= ia 0 == ( _ti need ia ) 1
            : b needb & >= ib 0 == ( _ti need ib ) 1
            ? needa { ( _g_ensure_grad tp ia ) } {}
            ? needb { ( _g_ensure_grad tp ib ) } {}
            // binops: broadcast-aware. Contributions are built through the
            // tensor package (broadcasting), then summed over broadcast axes
            // into each input's own shape by _g_acc_reduce.
            ? == op ( gop_add ) {
                : Tensor gv @ Tensor { . g dtype . g shape . g data }
                ? needa { ( _g_acc_reduce tp ia gv 1.0 ) } {}
                ? needb { ( _g_acc_reduce tp ib gv 1.0 ) } {}
            } {}
            ? == op ( gop_sub ) {
                : Tensor gv @ Tensor { . g dtype . g shape . g data }
                ? needa { ( _g_acc_reduce tp ia gv 1.0 ) } {}
                ? needb { ( _g_acc_reduce tp ib gv -1.0 ) } {}
            } {}
            ? == op ( gop_mul ) {
                : Tensor gv @ Tensor { . g dtype . g shape . g data }
                : Tensor av2 ( _g_view ( _g_val tp ia ) )
                : Tensor bv2 ( _g_view ( _g_val tp ib ) )
                ? needa {
                    ?? ( tensor_mul gv bv2 ) {
                        T ca → {
                            ( _g_acc_reduce tp ia ca 1.0 )
                            ( tensor_free ca )
                        }
                        F → {}
                    }
                } {}
                ? needb {
                    ?? ( tensor_mul gv av2 ) {
                        T cb → {
                            ( _g_acc_reduce tp ib cb 1.0 )
                            ( tensor_free cb )
                        }
                        F → {}
                    }
                } {}
            } {}
            ? == op ( gop_div ) {
                : Tensor gv @ Tensor { . g dtype . g shape . g data }
                : Tensor bv2 ( _g_view ( _g_val tp ib ) )
                : Tensor yv2 @ Tensor { . yv dtype . yv shape . yv data }
                ? needa {
                    ?? ( tensor_div gv bv2 ) {
                        T ca → {
                            ( _g_acc_reduce tp ia ca 1.0 )
                            ( tensor_free ca )
                        }
                        F → {}
                    }
                } {}
                ? needb {
                    ?? ( tensor_mul gv yv2 ) {
                        T t1 → {
                            ?? ( tensor_div t1 bv2 ) {
                                T cb → {
                                    ( _g_acc_reduce tp ib cb -1.0 )
                                    ( tensor_free cb )
                                }
                                F → {}
                            }
                            ( tensor_free t1 )
                        }
                        F → {}
                    }
                } {}
            } {}
            ? == op ( gop_neg ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : ~ i j 0
                ~ < j n {
                    ( vec_set [f] . ga data j - ( _tf . ga data j ) ( _tf . g data j ) )
                    = j + j 1
                }
            } {}
            ? == op ( gop_adds ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : ~ i j 0
                ~ < j n {
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) ( _tf . g data j ) )
                    = j + j 1
                }
            } {}
            ? == op ( gop_muls ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : f sc . nd s
                : ~ i j 0
                ~ < j n {
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) * ( _tf . g data j ) sc )
                    = j + j 1
                }
            } {}
            ? == op ( gop_relu ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : ~ i j 0
                ~ < j n {
                    ? > ( _tf . yv data j ) 0.0 {
                        ( vec_set [f] . ga data j + ( _tf . ga data j ) ( _tf . g data j ) )
                    } {}
                    = j + j 1
                }
            } {}
            ? == op ( gop_sigmoid ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : ~ i j 0
                ~ < j n {
                    : f yj ( _tf . yv data j )
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) * ( _tf . g data j ) * yj - 1.0 yj )
                    = j + j 1
                }
            } {}
            ? == op ( gop_tanh ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : ~ i j 0
                ~ < j n {
                    : f yj ( _tf . yv data j )
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) * ( _tf . g data j ) - 1.0 * yj yj )
                    = j + j 1
                }
            } {}
            ? == op ( gop_exp ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : ~ i j 0
                ~ < j n {
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) * ( _tf . g data j ) ( _tf . yv data j ) )
                    = j + j 1
                }
            } {}
            ? == op ( gop_log ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : *Tensor av # *Tensor ( _g_val tp ia )
                : ~ i j 0
                ~ < j n {
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) / ( _tf . g data j ) ( _tf . av data j ) )
                    = j + j 1
                }
            } {}
            ? == op ( gop_sqrt ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : ~ i j 0
                ~ < j n {
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) / ( _tf . g data j ) * 2.0 ( _tf . yv data j ) )
                    = j + j 1
                }
            } {}
            ? == op ( gop_sum ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : f g0 ( _tf . g data 0 )
                : i an ( vec_len [f] . ga data )
                : ~ i j 0
                ~ < j an {
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) g0 )
                    = j + j 1
                }
            } {}
            ? == op ( gop_mean ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : f g0 ( _tf . g data 0 )
                : i an ( vec_len [f] . ga data )
                : f gper / g0 # f an
                : ~ i j 0
                ~ < j an {
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) gper )
                    = j + j 1
                }
            } {}
            ? == op ( gop_matmul ) {
                // C[m,n] = A[m,k]·B[k,n]: dA[i,p] += Σ_j g[i,j]·B[p,j];
                // dB[p,j] += Σ_i A[i,p]·g[i,j]. Serial inner sums, row-major.
                // (an unneeded side's grad slot is NULL — deref only under
                // its need flag; the loops below are inside those guards)
                : *Tensor ga # *Tensor ? needa ( _g_grad_ptr tp ia ) # s 0
                : *Tensor gb # *Tensor ? needb ( _g_grad_ptr tp ib ) # s 0
                : *Tensor av # *Tensor ( _g_val tp ia )
                : *Tensor bv # *Tensor ( _g_val tp ib )
                : i M ( _ti . av shape 0 )
                : i K ( _ti . av shape 1 )
                : i N2 ( _ti . bv shape 1 )
                ? needa {
                    : ~ i i2 0
                    ~ < i2 M {
                        : ~ i p 0
                        ~ < p K {
                            : ~ f acc 0.0
                            : ~ i j 0
                            ~ < j N2 { = acc + acc * ( _tf . g data + * i2 N2 j ) ( _tf . bv data + * p N2 j ) = j + j 1 }
                            : i o + * i2 K p
                            ( vec_set [f] . ga data o + ( _tf . ga data o ) acc )
                            = p + p 1
                        }
                        = i2 + i2 1
                    }
                } {}
                ? needb {
                    : ~ i p2 0
                    ~ < p2 K {
                        : ~ i j2 0
                        ~ < j2 N2 {
                            : ~ f acc2 0.0
                            : ~ i i3 0
                            ~ < i3 M { = acc2 + acc2 * ( _tf . av data + * i3 K p2 ) ( _tf . g data + * i3 N2 j2 ) = i3 + i3 1 }
                            : i o2 + * p2 N2 j2
                            ( vec_set [f] . gb data o2 + ( _tf . gb data o2 ) acc2 )
                            = j2 + j2 1
                        }
                        = p2 + p2 1
                    }
                } {}
            } {}
            ? == op ( gop_bmm ) {
                // per-batch matmul backward, identical index math + batch offset
                : *Tensor ga # *Tensor ? needa ( _g_grad_ptr tp ia ) # s 0
                : *Tensor gb # *Tensor ? needb ( _g_grad_ptr tp ib ) # s 0
                : *Tensor av # *Tensor ( _g_val tp ia )
                : *Tensor bv # *Tensor ( _g_val tp ib )
                : i B2 ( _ti . av shape 0 )
                : i M ( _ti . av shape 1 )
                : i K ( _ti . av shape 2 )
                : i N2 ( _ti . bv shape 2 )
                : ~ i bb 0
                ~ < bb B2 {
                    : i ao * bb * M K
                    : i bo * bb * K N2
                    : i go * bb * M N2
                    ? needa {
                        : ~ i i2 0
                        ~ < i2 M {
                            : ~ i p 0
                            ~ < p K {
                                : ~ f acc 0.0
                                : ~ i j 0
                                ~ < j N2 { = acc + acc * ( _tf . g data + go + * i2 N2 j ) ( _tf . bv data + bo + * p N2 j ) = j + j 1 }
                                : i o + ao + * i2 K p
                                ( vec_set [f] . ga data o + ( _tf . ga data o ) acc )
                                = p + p 1
                            }
                            = i2 + i2 1
                        }
                    } {}
                    ? needb {
                        : ~ i p2 0
                        ~ < p2 K {
                            : ~ i j2 0
                            ~ < j2 N2 {
                                : ~ f acc2 0.0
                                : ~ i i3 0
                                ~ < i3 M { = acc2 + acc2 * ( _tf . av data + ao + * i3 K p2 ) ( _tf . g data + go + * i3 N2 j2 ) = i3 + i3 1 }
                                : i o2 + bo + * p2 N2 j2
                                ( vec_set [f] . gb data o2 + ( _tf . gb data o2 ) acc2 )
                                = j2 + j2 1
                            }
                            = p2 + p2 1
                        }
                    } {}
                    = bb + bb 1
                }
            } {}
            ? == op ( gop_transpose ) {
                // out is [N,M] of input [M,N]: ga[i,j] += g[j,i]
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : i M ( _ti . ga shape 0 )
                : i N2 ( _ti . ga shape 1 )
                : ~ i i2 0
                ~ < i2 M {
                    : ~ i j 0
                    ~ < j N2 {
                        : i o + * i2 N2 j
                        ( vec_set [f] . ga data o + ( _tf . ga data o ) ( _tf . g data + * j M i2 ) )
                        = j + j 1
                    }
                    = i2 + i2 1
                }
            } {}
            ? == op ( gop_reshape ) {
                // same row-major order, flat pass-through
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : ~ i j 0
                ~ < j n {
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) ( _tf . g data j ) )
                    = j + j 1
                }
            } {}
            ? == op ( gop_softmax ) {
                // dx = y ⊙ (g − Σ_axis(g⊙y)), per slice along the axis
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : i axis # i . nd s
                : i ndim ( vec_len [i] . yv shape )
                : ~ i outer 1
                : ~ i inner 1
                : i axlen ( _ti . yv shape axis )
                : ~ i d 0
                ~ < d axis { = outer * outer ( _ti . yv shape d ) = d + d 1 }
                = d + axis 1
                ~ < d ndim { = inner * inner ( _ti . yv shape d ) = d + d 1 }
                : ~ i o 0
                ~ < o outer {
                    : ~ i in2 0
                    ~ < in2 inner {
                        : ~ f dot 0.0
                        : ~ i t2 0
                        ~ < t2 axlen {
                            : i ix + + * * o axlen inner * t2 inner in2
                            = dot + dot * ( _tf . g data ix ) ( _tf . yv data ix )
                            = t2 + t2 1
                        }
                        = t2 0
                        ~ < t2 axlen {
                            : i ix + + * * o axlen inner * t2 inner in2
                            : f yj ( _tf . yv data ix )
                            ( vec_set [f] . ga data ix + ( _tf . ga data ix ) * yj - ( _tf . g data ix ) dot )
                            = t2 + t2 1
                        }
                        = in2 + in2 1
                    }
                    = o + o 1
                }
            } {}
            ? == op ( gop_slice ) {
                // scatter g back into the input window at aux.starts
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : s axp ?? ( vec_get [s] . tp aux k ) { T x → x F → # s 0 }
                : *GAux ax # *GAux axp
                : i ndim ( vec_len [i] . yv shape )
                : ( Vec i ) ost ( _t_strides . yv shape )
                : ( Vec i ) ist ( _t_strides . ga shape )
                : ~ i lin 0
                ~ < lin n {
                    : ~ i rem lin
                    : ~ i ioff 0
                    : ~ i d 0
                    ~ < d ndim {
                        : i st ( _ti ost d )
                        : i ix / rem st
                        = rem % rem st
                        = ioff + ioff * + ix ( _ti . ax starts d ) ( _ti ist d )
                        = d + d 1
                    }
                    ( vec_set [f] . ga data ioff + ( _tf . ga data ioff ) ( _tf . g data lin ) )
                    = lin + lin 1
                }
                ( vec_free [i] ost )
                ( vec_free [i] ist )
            } {}
            ? == op ( gop_concat ) {
                // split g along the axis at a's extent
                : *Tensor ga # *Tensor ? needa ( _g_grad_ptr tp ia ) # s 0
                : *Tensor gb # *Tensor ? needb ( _g_grad_ptr tp ib ) # s 0
                : i axis # i . nd s
                : i ndim ( vec_len [i] . yv shape )
                : i da ( _ti . ga shape axis )
                : i axlen ( _ti . yv shape axis )
                : ~ i outer 1
                : ~ i inner 1
                : ~ i d 0
                ~ < d axis { = outer * outer ( _ti . yv shape d ) = d + d 1 }
                = d + axis 1
                ~ < d ndim { = inner * inner ( _ti . yv shape d ) = d + d 1 }
                : ~ i o 0
                ~ < o outer {
                    : ~ i t2 0
                    ~ < t2 axlen {
                        : ~ i in2 0
                        ~ < in2 inner {
                            : i six + + * * o axlen inner * t2 inner in2
                            ? < t2 da {
                                ? needa {
                                    : i dix + + * * o da inner * t2 inner in2
                                    ( vec_set [f] . ga data dix + ( _tf . ga data dix ) ( _tf . g data six ) )
                                } {}
                            } {
                                ? needb {
                                    : i dix2 + + * * o - axlen da inner * - t2 da inner in2
                                    ( vec_set [f] . gb data dix2 + ( _tf . gb data dix2 ) ( _tf . g data six ) )
                                } {}
                            }
                            = in2 + in2 1
                        }
                        = t2 + t2 1
                    }
                    = o + o 1
                }
            } {}
        } {}
        = k - k 1
    }
    // With requires-grad propagation nothing ever writes into a no-need
    // slot (consts included), so their grad_of stays the zero tensor it
    // allocates on first touch — no epilogue sweep required.
    ( vec_free [i] need )
    ^ T
}
