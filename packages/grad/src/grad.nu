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
}

// ── construction / lifecycle ─────────────────────────────────────────

@ tape_new → *GTape {
    : *GTape tp # *GTape ( nurl_alloc Z GTape )
    = . tp ok 1
    = . tp nodes ( vec_new [GNode] )
    = . tp vals ( vec_new [s] )
    = . tp grads ( vec_new [s] )
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

@ tape_free * GTape tp → v {
    : i n ( vec_len [s] . tp vals )
    : ~ i k 0
    ~ < k n {
        ( _g_tfree ?? ( vec_get [s] . tp vals k ) { T x → x F → # s 0 } )
        ( _g_tfree ?? ( vec_get [s] . tp grads k ) { T x → x F → # s 0 } )
        = k + k 1
    }
    ( vec_free [s] . tp vals )
    ( vec_free [s] . tp grads )
    ( vec_free [GNode] . tp nodes )
    ( nurl_free # s tp )
}

@ tape_ok * GTape tp → b { ^ == . tp ok 1 }

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
        = k + k 1
    }
    : b _t1 ( vec_set_len [GNode] . tp nodes mark )
    : b _t2 ( vec_set_len [s] . tp vals mark )
    : b _t3 ( vec_set_len [s] . tp grads mark )
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

@ _g_binop * GTape tp GVar a GVar b i op → GVar {
    ? == . tp ok 1 {} { ^ @ GVar { -1 } }
    ? & >= . a id 0 >= . b id 0 {} { ^ ( _g_poison tp `binop on a poisoned input` ) }
    : s pa ( _g_val tp . a id )
    : s pb ( _g_val tp . b id )
    ? ( _g_same_shape pa pb ) {} { ^ ( _g_poison tp `binop shape mismatch (broadcast lands in M2 — use g_adds/g_muls for scalars)` ) }
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

// ── backward ─────────────────────────────────────────────────────────

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
    ( _g_ensure_grad tp top )
    : *Tensor gl # *Tensor ( _g_grad_ptr tp top )
    : i ln ( vec_len [f] . gl data )
    : ~ i q 0
    ~ < q ln { ( vec_set [f] . gl data q 1.0 ) = q + q 1 }
    : ~ i k top
    ~ >= k 0 {
        : GNode nd ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        : s gp ( _g_grad_ptr tp k )
        ? & != # i gp 0 > . nd op ( gop_const ) {
            : *Tensor g # *Tensor gp
            : *Tensor yv # *Tensor ( _g_val tp k )
            : i n ( vec_len [f] . g data )
            : i op . nd op
            : i ia . nd a
            : i ib . nd b
            ? >= ia 0 { ( _g_ensure_grad tp ia ) } {}
            ? >= ib 0 { ( _g_ensure_grad tp ib ) } {}
            ? == op ( gop_add ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : *Tensor gb # *Tensor ( _g_grad_ptr tp ib )
                : ~ i j 0
                ~ < j n {
                    : f gj ( _tf . g data j )
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) gj )
                    ( vec_set [f] . gb data j + ( _tf . gb data j ) gj )
                    = j + j 1
                }
            } {}
            ? == op ( gop_sub ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : *Tensor gb # *Tensor ( _g_grad_ptr tp ib )
                : ~ i j 0
                ~ < j n {
                    : f gj ( _tf . g data j )
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) gj )
                    ( vec_set [f] . gb data j - ( _tf . gb data j ) gj )
                    = j + j 1
                }
            } {}
            ? == op ( gop_mul ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : *Tensor gb # *Tensor ( _g_grad_ptr tp ib )
                : *Tensor av # *Tensor ( _g_val tp ia )
                : *Tensor bv # *Tensor ( _g_val tp ib )
                : ~ i j 0
                ~ < j n {
                    : f gj ( _tf . g data j )
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) * gj ( _tf . bv data j ) )
                    ( vec_set [f] . gb data j + ( _tf . gb data j ) * gj ( _tf . av data j ) )
                    = j + j 1
                }
            } {}
            ? == op ( gop_div ) {
                : *Tensor ga # *Tensor ( _g_grad_ptr tp ia )
                : *Tensor gb # *Tensor ( _g_grad_ptr tp ib )
                : *Tensor bv # *Tensor ( _g_val tp ib )
                : ~ i j 0
                ~ < j n {
                    : f gj ( _tf . g data j )
                    : f bj ( _tf . bv data j )
                    : f yj ( _tf . yv data j )
                    ( vec_set [f] . ga data j + ( _tf . ga data j ) / gj bj )
                    ( vec_set [f] . gb data j - ( _tf . gb data j ) / * gj yj bj )
                    = j + j 1
                }
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
        } {}
        = k - k 1
    }
    // Constants report a ZERO gradient. The sweep accumulates into every
    // input slot uniformly (leaves propagate nothing further, so a const's
    // accumulated value is never read by the sweep itself); zeroing here
    // keeps grad_of() honest without a per-write requires-grad branch in
    // every op loop.
    = k 0
    ~ <= k top {
        : GNode nd2 ?? ( vec_get [GNode] . tp nodes k ) { T x → x F → @ GNode { -1 -1 -1 0.0 } }
        ? == . nd2 op ( gop_const ) {
            : s gp2 ( _g_grad_ptr tp k )
            ? != # i gp2 0 {
                : *Tensor gz # *Tensor gp2
                : i zn ( vec_len [f] . gz data )
                : ~ i j2 0
                ~ < j2 zn { ( vec_set [f] . gz data j2 0.0 ) = j2 + j2 1 }
            } {}
        } {}
        = k + k 1
    }
    ^ T
}
