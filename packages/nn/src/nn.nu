// nn.nu — neural-network layers on the grad autograd tape.
//
// Every layer here is a pure TAPE BUILDER: it takes a `* GTape` and input
// `GVar`s (activations and pre-registered weight/const GVars) and returns a
// `GVar`, recording ordinary grad ops. Nothing here owns parameters or
// touches the device — the caller registers weights with grad_param /
// grad_const, calls backward(loss) once, and grad derives every gradient.
// Device replay (gput) and megakernel fusion (gpfuse) therefore come free,
// because an nn graph is just a grad graph.
//
// The math is lifted verbatim from two places that had proven it and were
// drifting apart: grad's PyTorch-float64 LoRA-block oracle
// (grad/tests/lora_block.nu + lora_oracle.sh, loss and all 14 adapter
// gradients to 1e-11) and nurllama's finetune path (__ft_rms / __ft_lora_lin
// / __ft_rope / __ft_headslice). This package is the single home for that
// math; the two new layers (nn_layernorm, nn_swiglu) carry their own
// finite-difference checks.
//
// Convention: 2-D activations are [rows=T, cols]. A weight is [in, out]
// (x[T,in] · W[in,out]); a bias / norm-weight is a [out] row broadcast over
// rows. Row reductions (rmsnorm/layernorm mean) use a shared ones-column
// [n,1] the caller threads in via nn_ones, so a block builds it once.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/grad/src/grad.nu`
$ `deps/tensor/src/tensor.nu`

// ── const helpers ─────────────────────────────────────────────────────

// A [rows, cols] (or [cols] when rows==0) const tensor from flat data.
@ nn_const * GTape tp ( Vec f ) v i rows i cols → GVar {
    : ( Vec i ) s ( vec_new [i] )
    ? > rows 0 { ( vec_push [i] s rows ) } {}
    ( vec_push [i] s cols )
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar o ( grad_const tp t )
    ( tensor_free t )
    ^ o
}

// A [rows, cols] parameter tensor from flat data (registered for grad).
@ nn_param * GTape tp ( Vec f ) v i rows i cols → GVar {
    : ( Vec i ) s ( vec_new [i] )
    ? > rows 0 { ( vec_push [i] s rows ) } {}
    ( vec_push [i] s cols )
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar o ( grad_param tp t )
    ( tensor_free t )
    ^ o
}

// A ones column [n,1] — the row-reduction operand for the norms.
@ nn_ones * GTape tp i n → GVar {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 1.0 ) = k + k 1 }
    : GVar o ( nn_const tp v n 1 )
    ( vec_free [f] v )
    ^ o
}

// ── linear ─────────────────────────────────────────────────────────────

// x[T,in] · W[in,out].
@ nn_linear * GTape tp GVar x GVar w → GVar {
    ^ ( g_matmul tp x w )
}

// x[T,in] · W[in,out] + b[out] (bias broadcast over rows).
@ nn_linear_bias * GTape tp GVar x GVar w GVar b → GVar {
    ^ ( g_add tp ( g_matmul tp x w ) b )
}

// LoRA linear: x·W0 + scale·(x·A)·B, with A[in,r], B[r,out], scale = α/r.
// W0 is typically a frozen const; A/B are the trainable params.
@ nn_lora_linear * GTape tp GVar x GVar w0 GVar a GVar b f scale → GVar {
    : GVar base ( g_matmul tp x w0 )
    : GVar delta ( g_muls tp ( g_matmul tp ( g_matmul tp x a ) b ) scale )
    ^ ( g_add tp base delta )
}

// ── normalization ──────────────────────────────────────────────────────

// RMSNorm: x ⊙ rsqrt(mean(x²)+eps) ⊙ w. `ones` is a [h,1] column;
// the row mean is x²·ones / h.
@ nn_rmsnorm * GTape tp GVar x GVar w GVar ones i h f eps → GVar {
    : GVar x2 ( g_mul tp x x )
    : GVar m ( g_muls tp ( g_matmul tp x2 ones ) / 1.0 # f h )
    : GVar d ( g_sqrt tp ( g_adds tp m eps ) )
    ^ ( g_mul tp ( g_div tp x d ) w )
}

// LayerNorm: (x - mean) / sqrt(var + eps) ⊙ w + b, per row over `h`
// features. mean = x·ones/h; var = mean((x-mean)²) = (x-mean)²·ones/h.
// `w` is [h] (scale), `b` is [h] (shift); `ones` is [h,1].
@ nn_layernorm * GTape tp GVar x GVar w GVar b GVar ones i h f eps → GVar {
    : GVar mean ( g_muls tp ( g_matmul tp x ones ) / 1.0 # f h )  // [T,1]
    : GVar xc ( g_sub tp x mean )  // broadcast [T,1] over [T,h]
    : GVar var ( g_muls tp ( g_matmul tp ( g_mul tp xc xc ) ones ) / 1.0 # f h )
    : GVar d ( g_sqrt tp ( g_adds tp var eps ) )
    ^ ( g_add tp ( g_mul tp ( g_div tp xc d ) w ) b )
}

// ── activations ────────────────────────────────────────────────────────

// SiLU / swish: x · sigmoid(x).
@ nn_silu * GTape tp GVar x → GVar {
    ^ ( g_mul tp x ( g_sigmoid tp x ) )
}

// SwiGLU: SiLU(gate) ⊙ up — the gated-MLP activation (gate, up are the two
// projections of the same input).
@ nn_swiglu * GTape tp GVar gate GVar up → GVar {
    ^ ( g_mul tp ( nn_silu tp gate ) up )
}

// Softmax over `axis` — named alias of grad's op for symmetry.
@ nn_softmax * GTape tp GVar x i axis → GVar {
    ^ ( g_softmax tp x axis )
}

// ── positional (rotary) ────────────────────────────────────────────────

// Fill NEOX/half-split rope tables cos/sin for `t` positions × `hd/2`
// frequencies, θ_j = base^(-2j/hd). Host-side; the caller const-ifies the
// two [t, hd/2] vectors (nn_const ... t half).
@ nn_rope_fill i t i hd f base ( Vec f ) cos_out ( Vec f ) sin_out → v {
    : i half / hd 2
    : ~ i p 0
    ~ < p t {
        : ~ i j 0
        ~ < j half {
            : f fr ( pow base / * -2.0 # f j # f hd )
            : f ang * # f p fr
            ( vec_push [f] cos_out ( float_cos ang ) )
            ( vec_push [f] sin_out ( float_sin ang ) )
            = j + j 1
        }
        = p + p 1
    }
}

// NEOX half-split rope on one [t, hd] head: split into halves x1,x2 and
// rotate — [x1·cos - x2·sin, x2·cos + x1·sin]. cosc/sinc are [t, hd/2].
@ nn_rope * GTape tp GVar h GVar cosc GVar sinc i t i hd → GVar {
    : i half / hd 2
    : ( Vec i ) st1 ( vec_new [i] )
    ( vec_push [i] st1 0 ) ( vec_push [i] st1 0 )
    : ( Vec i ) sp1 ( vec_new [i] )
    ( vec_push [i] sp1 t ) ( vec_push [i] sp1 half )
    : GVar x1 ( g_slice tp h st1 sp1 )
    : ( Vec i ) st2 ( vec_new [i] )
    ( vec_push [i] st2 0 ) ( vec_push [i] st2 half )
    : ( Vec i ) sp2 ( vec_new [i] )
    ( vec_push [i] sp2 t ) ( vec_push [i] sp2 hd )
    : GVar x2 ( g_slice tp h st2 sp2 )
    ( vec_free [i] st1 ) ( vec_free [i] sp1 )
    ( vec_free [i] st2 ) ( vec_free [i] sp2 )
    : GVar r1 ( g_sub tp ( g_mul tp x1 cosc ) ( g_mul tp x2 sinc ) )
    : GVar r2 ( g_add tp ( g_mul tp x2 cosc ) ( g_mul tp x1 sinc ) )
    ^ ( g_concat tp r1 r2 1 )
}

// ── attention ──────────────────────────────────────────────────────────

// Slice head `hi` of a [t, n*hd] projection: columns [hi*hd, hi*hd+hd).
@ nn_head * GTape tp GVar q i t i hi i hd → GVar {
    : i off * hi hd
    : ( Vec i ) st ( vec_new [i] )
    ( vec_push [i] st 0 ) ( vec_push [i] st off )
    : ( Vec i ) sp ( vec_new [i] )
    ( vec_push [i] sp t ) ( vec_push [i] sp + off hd )
    : GVar o ( g_slice tp q st sp )
    ( vec_free [i] st ) ( vec_free [i] sp )
    ^ o
}

// Fill a causal mask [t, t]: 0 on/below the diagonal, -1e9 above.
@ nn_causal_mask_fill i t ( Vec f ) out → v {
    : ~ i r 0
    ~ < r t {
        : ~ i c 0
        ~ < c t { ( vec_push [f] out ? > c r -1000000000.0 0.0 ) = c + c 1 }
        = r + r 1
    }
}

// Grouped-query attention over pre-projected q[t,nh*hd], k/v[t,nkv*hd].
// RoPE is applied to each q/k head; `nkv` key/value heads are shared across
// `nh` query heads (kv index = qi / (nh/nkv)). `mask` is [t,t]; `iscale` is
// the 1/sqrt(hd) score scale. Returns the concatenated context [t, nh*hd].
@ nn_gqa_attention * GTape tp GVar q GVar k GVar v GVar cosc GVar sinc GVar mask i t i nh i nkv i hd f iscale → GVar {
    : i group / nh nkv
    : ~ GVar ctx @ GVar { -1 }
    : ~ i qi 0
    ~ < qi nh {
        : i kvi / qi group
        : GVar qh ( nn_rope tp ( nn_head tp q t qi hd ) cosc sinc t hd )
        : GVar kh ( nn_rope tp ( nn_head tp k t kvi hd ) cosc sinc t hd )
        : GVar vh ( nn_head tp v t kvi hd )
        : GVar sc ( g_muls tp ( g_matmul tp qh ( g_transpose tp kh ) ) iscale )
        : GVar aw ( g_softmax tp ( g_add tp sc mask ) 1 )
        : GVar ch ( g_matmul tp aw vh )
        ? < . ctx id 0 { = ctx ch } { = ctx ( g_concat tp ctx ch 1 ) }
        = qi + qi 1
    }
    ^ ctx
}

// ── loss ───────────────────────────────────────────────────────────────

// Cross-entropy for next-token / classification over [rows, V] logits with
// a one-hot target [rows, V]. picked = (softmax(logits) ⊙ onehot)·onesV is
// the target probability per row; CE = -mean(log(picked)). `onesV` is a
// [V,1] column. (Rows whose onehot is all-zero contribute log(0); slice or
// mask those out upstream — see nn_cross_entropy_rows.)
@ nn_cross_entropy * GTape tp GVar logits GVar onehot GVar onesV → GVar {
    : GVar probs ( g_softmax tp logits 1 )
    : GVar picked ( g_matmul tp ( g_mul tp probs onehot ) onesV )
    ^ ( g_neg tp ( g_mean tp ( g_log tp picked ) ) )
}

// Cross-entropy over the FIRST `keep` rows only (next-token training leaves
// the last position without a target; keep = rows-1). Slices the picked
// column to [keep,1] before the log-mean.
@ nn_cross_entropy_rows * GTape tp GVar logits GVar onehot GVar onesV i keep → GVar {
    : GVar probs ( g_softmax tp logits 1 )
    : GVar picked ( g_matmul tp ( g_mul tp probs onehot ) onesV )
    : ( Vec i ) st ( vec_new [i] )
    ( vec_push [i] st 0 ) ( vec_push [i] st 0 )
    : ( Vec i ) sp ( vec_new [i] )
    ( vec_push [i] sp keep ) ( vec_push [i] sp 1 )
    : GVar pick2 ( g_slice tp picked st sp )
    ( vec_free [i] st ) ( vec_free [i] sp )
    ^ ( g_neg tp ( g_mean tp ( g_log tp pick2 ) ) )
}
