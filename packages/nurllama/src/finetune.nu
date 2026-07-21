// nurllama/finetune.nu — LoRA finetuning over the grad tape (M6b).
//
// Loads a GGUF model's weights as f64 HOST tensors (gguf_dequant_f64 —
// independent of the quantised GPU inference path) and builds the whole
// transformer forward + cross-entropy loss as ONE grad-tape graph, with
// LoRA adapter pairs (A[in,r], B[r,out], y = x·W0 + (α/r)·(x·A)·B) on
// q/k/v/o and gate/up/down as the only parameters. Train by capturing the
// episode with gput and replaying on the device; the frozen base weights
// cost no gradient memory or backward compute (grad 0.3.0's requires-grad
// propagation).
//
// Architectures: llama-family and qwen2 (bias'd q/k/v, NEOX rope). The
// llama family's NORM-style rope rotates ADJACENT lanes (2j, 2j+1), which
// a contiguous-slice tape cannot express — so the loader UN-PERMUTES the
// q/k projection columns per head (evens first, odds second) and the graph
// applies half-split NEOX rope: every pair sees the identical rotation at
// a permuted lane, and attention scores are permutation-invariant, so the
// values downstream are exactly the model's. (v is untouched — context and
// o-proj stay in the original layout.)
//
// Layouts: GGUF stores [out, in] row-major; the tape multiplies x[T,in] ·
// W[in,out], so every weight is transposed once at load. Embedding lookup
// happens HOST-side (the rows enter the tape as a const; embeddings are
// frozen, so no gather op is needed). Tied-embedding models reuse
// token_embd for the lm_head (transposed the other way).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/gguf/src/gguf.nu`
$ `deps/gguf/src/dequant.nu`
$ `deps/grad/src/grad.nu`
$ `deps/grad/src/gput.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

// A heap-boxed f64 vector (NURL has no bare deref for *( Vec f ) — field
// access through a struct pointer is the idiom).
: FtV {
    ( Vec f ) v
}

// One weight in tape layout: data [rows=in, cols=out] flat.
: FtW {
    i rows
    i cols
    ( Vec f ) data
}

: FtModel {
    b ok
    i n_embd
    i n_layer
    i n_head
    i n_kv
    i head_dim
    i n_ff
    i n_vocab
    f eps
    f rope_base
    i rope_dim
    i rope_style  // 0 llama/NORM (columns un-permuted at load) · 1 NEOX
    ( Vec f ) embd  // [n_vocab, n_embd] row-major (host lookup table)
    FtW wout  // lm_head [n_embd, n_vocab] (tied → transposed embd)
    ( Vec f ) norm_f  // output_norm [n_embd]
    ( Vec FtW ) wq ( Vec FtW ) wk ( Vec FtW ) wv ( Vec FtW ) wo
    ( Vec FtW ) wg ( Vec FtW ) wu ( Vec FtW ) wd
    ( Vec s ) bq ( Vec s ) bk ( Vec s ) bv  // *( Vec f ) or 0 (qwen2 bias)
    ( Vec s ) an ( Vec s ) fn  // attn_norm / ffn_norm, *( Vec f ) per layer
}

@ __ft_wfree FtW w → v { ( vec_free [f] . w data ) }

@ __ft_vfree ( Vec s ) v → v {
    : ~ i k 0
    ~ < k ( vec_len [s] v ) {
        : s p ?? ( vec_get [s] v k ) { T x → x F → # s 0 }
        ? != # i p 0 {
            : *FtV pv # *FtV p
            ( vec_free [f] . pv v )
            ( nurl_free p )
        } {}
        = k + k 1
    }
    ( vec_free [s] v )
}

@ ft_free * FtModel m → v {
    ( vec_free [f] . m embd )
    ( __ft_wfree . m wout )
    ( vec_free [f] . m norm_f )
    : ~ i k 0
    ~ < k ( vec_len [FtW] . m wq ) {
        ?? ( vec_get [FtW] . m wq k ) { T w → { ( __ft_wfree w ) } F _ → {} }
        ?? ( vec_get [FtW] . m wk k ) { T w → { ( __ft_wfree w ) } F _ → {} }
        ?? ( vec_get [FtW] . m wv k ) { T w → { ( __ft_wfree w ) } F _ → {} }
        ?? ( vec_get [FtW] . m wo k ) { T w → { ( __ft_wfree w ) } F _ → {} }
        ?? ( vec_get [FtW] . m wg k ) { T w → { ( __ft_wfree w ) } F _ → {} }
        ?? ( vec_get [FtW] . m wu k ) { T w → { ( __ft_wfree w ) } F _ → {} }
        ?? ( vec_get [FtW] . m wd k ) { T w → { ( __ft_wfree w ) } F _ → {} }
        = k + k 1
    }
    ( vec_free [FtW] . m wq ) ( vec_free [FtW] . m wk ) ( vec_free [FtW] . m wv )
    ( vec_free [FtW] . m wo ) ( vec_free [FtW] . m wg ) ( vec_free [FtW] . m wu )
    ( vec_free [FtW] . m wd )
    ( __ft_vfree . m bq ) ( __ft_vfree . m bk ) ( __ft_vfree . m bv )
    ( __ft_vfree . m an ) ( __ft_vfree . m fn )
    ( nurl_free # s m )
}

// Dequant tensor `name` to f64. GGUF layout [out, in] flat (in fastest).
@ __ft_raw * Gguf gg s name * u rowsb * u colsb → ( Vec f ) {
    : i idx ( gguf_find_tensor gg name )
    ? >= idx 0 {} { ^ ( vec_new [f] ) }
    : GgufTensor t ?? ( vec_get [GgufTensor] . gg tensors idx ) {
        T x → x
        F → @ GgufTensor { ( string_new ) 0 0 0 0 0 0 0 0 0 }
    }
    ?? ( gguf_dequant_f64 gg idx ) {
        T v → {
            ( nurl_poke rowsb 0 . t d1 )  // out
            ( nurl_poke colsb 0 . t d0 )  // in
            ^ v
        }
        F e → {
            ( string_free e )
            ^ ( vec_new [f] )
        }
    }
}

// [out, in] flat → tape FtW [in, out].
@ __ft_transpose ( Vec f ) src i out i in → FtW {
    : ( Vec f ) d ( vec_with_cap [f] * out in )
    : ~ i k 0
    ~ < k * out in { ( vec_push [f] d 0.0 ) = k + k 1 }
    : ~ i o 0
    ~ < o out {
        : ~ i i2 0
        ~ < i2 in {
            ( vec_set [f] d + * i2 out o ( _tf src + * o in i2 ) )
            = i2 + i2 1
        }
        = o + o 1
    }
    ^ @ FtW { in out d }
}

// Un-permute NORM-rope q/k columns per head IN TAPE LAYOUT: for head h,
// new col (h·hd + j) = old col (h·hd + 2j), new (h·hd + hd/2 + j) = old
// (h·hd + 2j + 1). After this, half-split NEOX rope computes the model's
// exact rotations (at permuted lanes; scores are permutation-invariant).
@ __ft_unperm FtW w i heads i hd → v {
    : i half / hd 2
    : i rows . w rows
    : i cols . w cols
    : ( Vec f ) tmp ( vec_with_cap [f] cols )
    : ~ i c 0
    ~ < c cols { ( vec_push [f] tmp 0.0 ) = c + c 1 }
    : ~ i r 0
    ~ < r rows {
        : i base * r cols
        : ~ i h 0
        ~ < h heads {
            : ~ i j 0
            ~ < j half {
                ( vec_set [f] tmp + * h hd j ( _tf . w data + base + * h hd * 2 j ) )
                ( vec_set [f] tmp + * h hd + half j ( _tf . w data + base + * h hd + * 2 j 1 ) )
                = j + j 1
            }
            = h + h 1
        }
        = c 0
        ~ < c cols { ( vec_set [f] . w data + base c ( _tf tmp c ) ) = c + c 1 }
        = r + r 1
    }
    ( vec_free [f] tmp )
}

// Same un-permutation for a bias vector (one row).
@ __ft_unperm_vec * FtV p i heads i hd → v {
    : FtW w @ FtW { 1 * heads hd . p v }
    ( __ft_unperm w heads hd )
}

@ __ft_lname i layer s suffix → String {
    : String s ( string_from `blk.` )
    ( string_push_str s ( nurl_str_int layer ) )
    ( string_push_str s `.` )
    ( string_push_str s suffix )
    ^ s
}

// A layer weight in tape layout (poisons `okb` on a missing tensor).
@ __ft_lw * Gguf gg i layer s suffix * u okb → FtW {
    : String nm ( __ft_lname layer suffix )
    : *u rb ( nurl_alloc 8 )
    : *u cb ( nurl_alloc 8 )
    : ( Vec f ) raw ( __ft_raw gg ( string_data nm ) rb cb )
    ( string_free nm )
    ? > ( vec_len [f] raw ) 0 {} {
        ( nurl_poke okb 0 0 )
        ( nurl_free rb ) ( nurl_free cb )
        ( vec_free [f] raw )
        ^ @ FtW { 0 0 ( vec_new [f] ) }
    }
    : FtW w ( __ft_transpose raw ( nurl_peek rb 0 ) ( nurl_peek cb 0 ) )
    ( vec_free [f] raw )
    ( nurl_free rb ) ( nurl_free cb )
    ^ w
}

// An optional 1-D tensor (norm weight / bias) → heap *( Vec f ) or 0.
@ __ft_lvec * Gguf gg i layer s suffix → s {
    : String nm ( __ft_lname layer suffix )
    : *u rb ( nurl_alloc 8 )
    : *u cb ( nurl_alloc 8 )
    : ( Vec f ) raw ( __ft_raw gg ( string_data nm ) rb cb )
    ( string_free nm ) ( nurl_free rb ) ( nurl_free cb )
    ? > ( vec_len [f] raw ) 0 {} { ( vec_free [f] raw ) ^ # s 0 }
    : *FtV p # *FtV ( nurl_alloc Z FtV )
    = . p v raw
    ^ # s p
}

// Open a GGUF and lift every weight into tape-ready f64 host tensors.
@ ft_open s path → !*FtModel String {
    ?? ( gguf_open path ) {
        T gg → {
            : s arch ( gguf_kv_str_or gg `general.architecture` `` )
            : *FtModel m # *FtModel ( nurl_alloc Z FtModel )
            = . m ok T
            : String kb ( string_from arch )
            ( string_push_str kb `.embedding_length` )
            = . m n_embd ( gguf_kv_int_or gg ( string_data kb ) 0 )
            ( string_free kb )
            : String kb2 ( string_from arch )
            ( string_push_str kb2 `.block_count` )
            = . m n_layer ( gguf_kv_int_or gg ( string_data kb2 ) 0 )
            ( string_free kb2 )
            : String kb3 ( string_from arch )
            ( string_push_str kb3 `.attention.head_count` )
            = . m n_head ( gguf_kv_int_or gg ( string_data kb3 ) 0 )
            ( string_free kb3 )
            : String kb4 ( string_from arch )
            ( string_push_str kb4 `.attention.head_count_kv` )
            = . m n_kv ( gguf_kv_int_or gg ( string_data kb4 ) . m n_head )
            ( string_free kb4 )
            : String kb5 ( string_from arch )
            ( string_push_str kb5 `.attention.layer_norm_rms_epsilon` )
            = . m eps ( gguf_kv_f_or gg ( string_data kb5 ) 0.00001 )
            ( string_free kb5 )
            : String kb6 ( string_from arch )
            ( string_push_str kb6 `.rope.freq_base` )
            = . m rope_base ( gguf_kv_f_or gg ( string_data kb6 ) 10000.0 )
            ( string_free kb6 )
            ? > . m n_head 0 { = . m head_dim / . m n_embd . m n_head } {}
            : String kb7 ( string_from arch )
            ( string_push_str kb7 `.rope.dimension_count` )
            = . m rope_dim ( gguf_kv_int_or gg ( string_data kb7 ) . m head_dim )
            ( string_free kb7 )
            = . m rope_style ? == ( nurl_str_eq arch `qwen2` ) 1 1 0
            ? & > . m n_embd 0 > . m n_layer 0 {} {
                ( gguf_close gg )
                ( nurl_free # s m )
                ^ @ !*FtModel String { F ( string_from `finetune: not a llama/qwen2 GGUF` ) }
            }
            // embeddings [vocab, n_embd]
            : *u rb ( nurl_alloc 8 )
            : *u cb ( nurl_alloc 8 )
            = . m embd ( __ft_raw gg `token_embd.weight` rb cb )
            = . m n_vocab ( nurl_peek rb 0 )
            ? > ( vec_len [f] . m embd ) 0 {} { = . m ok F }
            // lm_head: output.weight, or the tied embedding table
            : i oi ( gguf_find_tensor gg `output.weight` )
            ? >= oi 0 {
                : *u rb2 ( nurl_alloc 8 )
                : *u cb2 ( nurl_alloc 8 )
                : ( Vec f ) raw ( __ft_raw gg `output.weight` rb2 cb2 )
                = . m wout ( __ft_transpose raw ( nurl_peek rb2 0 ) ( nurl_peek cb2 0 ) )
                ( vec_free [f] raw )
                ( nurl_free rb2 ) ( nurl_free cb2 )
            } {
                = . m wout ( __ft_transpose . m embd . m n_vocab . m n_embd )
            }
            : *u rb3 ( nurl_alloc 8 )
            : *u cb3 ( nurl_alloc 8 )
            = . m norm_f ( __ft_raw gg `output_norm.weight` rb3 cb3 )
            ( nurl_free rb3 ) ( nurl_free cb3 )
            ( nurl_free rb ) ( nurl_free cb )
            = . m wq ( vec_new [FtW] )
            = . m wk ( vec_new [FtW] )
            = . m wv ( vec_new [FtW] )
            = . m wo ( vec_new [FtW] )
            = . m wg ( vec_new [FtW] )
            = . m wu ( vec_new [FtW] )
            = . m wd ( vec_new [FtW] )
            = . m bq ( vec_new [s] )
            = . m bk ( vec_new [s] )
            = . m bv ( vec_new [s] )
            = . m an ( vec_new [s] )
            = . m fn ( vec_new [s] )
            : *u okb ( nurl_alloc 8 )
            ( nurl_poke okb 0 1 )
            // ffn size read from the first gate tensor
            = . m n_ff 0
            : ~ i L 0
            ~ < L . m n_layer {
                : FtW q ( __ft_lw gg L `attn_q.weight` okb )
                : FtW k2 ( __ft_lw gg L `attn_k.weight` okb )
                ? == . m rope_style 0 {
                    ( __ft_unperm q . m n_head . m head_dim )
                    ( __ft_unperm k2 . m n_kv . m head_dim )
                } {}
                ( vec_push [FtW] . m wq q )
                ( vec_push [FtW] . m wk k2 )
                ( vec_push [FtW] . m wv ( __ft_lw gg L `attn_v.weight` okb ) )
                ( vec_push [FtW] . m wo ( __ft_lw gg L `attn_output.weight` okb ) )
                : FtW g2 ( __ft_lw gg L `ffn_gate.weight` okb )
                ? == . m n_ff 0 { = . m n_ff . g2 cols } {}
                ( vec_push [FtW] . m wg g2 )
                ( vec_push [FtW] . m wu ( __ft_lw gg L `ffn_up.weight` okb ) )
                ( vec_push [FtW] . m wd ( __ft_lw gg L `ffn_down.weight` okb ) )
                : s bqp ( __ft_lvec gg L `attn_q.bias` )
                : s bkp ( __ft_lvec gg L `attn_k.bias` )
                ? & == . m rope_style 0 != # i bqp 0 {
                    : *FtV pq # *FtV bqp
                    ( __ft_unperm_vec pq . m n_head . m head_dim )
                } {}
                ? & == . m rope_style 0 != # i bkp 0 {
                    : *FtV pk # *FtV bkp
                    ( __ft_unperm_vec pk . m n_kv . m head_dim )
                } {}
                ( vec_push [s] . m bq bqp )
                ( vec_push [s] . m bk bkp )
                ( vec_push [s] . m bv ( __ft_lvec gg L `attn_v.bias` ) )
                ( vec_push [s] . m an ( __ft_lvec gg L `attn_norm.weight` ) )
                ( vec_push [s] . m fn ( __ft_lvec gg L `ffn_norm.weight` ) )
                = L + L 1
            }
            ? == ( nurl_peek okb 0 ) 1 {} { = . m ok F }
            ( nurl_free okb )
            ( gguf_close gg )
            ? . m ok {} {
                : *FtModel m2 m
                ( ft_free m2 )
                ^ @ !*FtModel String { F ( string_from `finetune: missing tensors in GGUF` ) }
            }
            ^ @ !*FtModel String { T m }
        }
        F e → { ^ @ !*FtModel String { F e } }
    }
}

// ── the tape graph ────────────────────────────────────────────────────

// Host-side embedding lookup: token ids → [T, n_embd] rows.
@ ft_embed * FtModel m ( Vec i ) ids → ( Vec f ) {
    : i T2 ( vec_len [i] ids )
    : ( Vec f ) x ( vec_with_cap [f] * T2 . m n_embd )
    : ~ i t 0
    ~ < t T2 {
        : i id ( _ti ids t )
        : ~ i c 0
        ~ < c . m n_embd {
            ( vec_push [f] x ( _tf . m embd + * id . m n_embd c ) )
            = c + c 1
        }
        = t + t 1
    }
    ^ x
}

@ __ft_const * GTape tp ( Vec f ) v i r i c → GVar {
    : ( Vec i ) s ( vec_new [i] )
    ? > r 0 { ( vec_push [i] s r ) } {}
    ( vec_push [i] s c )
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar o ( grad_const tp t )
    ( tensor_free t )
    ^ o
}

@ __ft_ones * GTape tp i n → GVar {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 1.0 ) = k + k 1 }
    : GVar o ( __ft_const tp v n 1 )
    ( vec_free [f] v )
    ^ o
}

@ __ft_rms * GTape tp GVar x GVar w GVar ones i h f eps → GVar {
    : GVar x2 ( g_mul tp x x )
    : GVar mn ( g_muls tp ( g_matmul tp x2 ones ) / 1.0 # f h )
    : GVar d ( g_sqrt tp ( g_adds tp mn eps ) )
    ^ ( g_mul tp ( g_div tp x d ) w )
}

// LoRA pair registration: A [in,r] seeded small, B [r,out] zero.
@ __ft_lora_pair * GTape tp Rng rg i in i r i out * u pids i slot → v {
    : ( Vec f ) av ( vec_with_cap [f] * in r )
    : f lim / 1.0 ( float_sqrt # f in )
    : ~ i k 0
    ~ < k * in r { ( vec_push [f] av * lim - * 2.0 ( rng_u01 rg ) 1.0 ) = k + k 1 }
    : ( Vec i ) as2 ( vec_new [i] )
    ( vec_push [i] as2 in ) ( vec_push [i] as2 r )
    : Tensor at ( tensor_from_data TE_F64 as2 av )
    : GVar pa ( grad_param tp at )
    ( tensor_free at ) ( vec_free [f] av )
    : ( Vec f ) bv ( vec_with_cap [f] * r out )
    = k 0
    ~ < k * r out { ( vec_push [f] bv 0.0 ) = k + k 1 }
    : ( Vec i ) bs ( vec_new [i] )
    ( vec_push [i] bs r ) ( vec_push [i] bs out )
    : Tensor bt ( tensor_from_data TE_F64 bs bv )
    : GVar pb ( grad_param tp bt )
    ( tensor_free bt ) ( vec_free [f] bv )
    ( nurl_poke pids * slot 2 . pa id )
    ( nurl_poke pids + * slot 2 1 . pb id )
}

@ __ft_lora_lin * GTape tp GVar x GVar w0 * u pids i slot f scale → GVar {
    : GVar pa @ GVar { ( nurl_peek pids * slot 2 ) }
    : GVar pb @ GVar { ( nurl_peek pids + * slot 2 1 ) }
    : GVar base ( g_matmul tp x w0 )
    ^ ( g_add tp base ( g_muls tp ( g_matmul tp ( g_matmul tp x pa ) pb ) scale ) )
}

@ __ft_headslice * GTape tp GVar q i T2 i off i hd → GVar {
    : ( Vec i ) st ( vec_new [i] )
    ( vec_push [i] st 0 ) ( vec_push [i] st off )
    : ( Vec i ) sp ( vec_new [i] )
    ( vec_push [i] sp T2 ) ( vec_push [i] sp + off hd )
    : GVar o ( g_slice tp q st sp )
    ( vec_free [i] st ) ( vec_free [i] sp )
    ^ o
}

@ __ft_rope * GTape tp GVar h GVar cosc GVar sinc i T2 i hd → GVar {
    : i half / hd 2
    : ( Vec i ) st1 ( vec_new [i] )
    ( vec_push [i] st1 0 ) ( vec_push [i] st1 0 )
    : ( Vec i ) sp1 ( vec_new [i] )
    ( vec_push [i] sp1 T2 ) ( vec_push [i] sp1 half )
    : GVar x1 ( g_slice tp h st1 sp1 )
    : ( Vec i ) st2 ( vec_new [i] )
    ( vec_push [i] st2 0 ) ( vec_push [i] st2 half )
    : ( Vec i ) sp2 ( vec_new [i] )
    ( vec_push [i] sp2 T2 ) ( vec_push [i] sp2 hd )
    : GVar x2 ( g_slice tp h st2 sp2 )
    ( vec_free [i] st1 ) ( vec_free [i] sp1 ) ( vec_free [i] st2 ) ( vec_free [i] sp2 )
    : GVar r1 ( g_sub tp ( g_mul tp x1 cosc ) ( g_mul tp x2 sinc ) )
    : GVar r2 ( g_add tp ( g_mul tp x2 cosc ) ( g_mul tp x1 sinc ) )
    ^ ( g_concat tp r1 r2 1 )
}

// The result handles of one built graph.
: FtG {
    GVar loss
    GVar logits
    i n_pairs  // LoRA pairs registered (7 per layer)
}

// Build the full forward + next-token CE loss on `tp`. `ids` is one
// sequence (T tokens; loss over positions 0..T-2 predicting 1..T-1).
// `pids` must hold 2·7·n_layer i64 slots; LoRA params register FIRST.
@ ft_graph * FtModel m * GTape tp ( Vec i ) ids i r f alpha i seed * u pids → FtG {
    : i T2 ( vec_len [i] ids )
    : i H . m n_embd
    : i hd . m head_dim
    : i NH . m n_head
    : i NKV . m n_kv
    : f scale / alpha # f r
    ? == . m rope_dim hd {} {
        : GVar bad ( _g_poison tp `finetune: partial rotary not supported` )
        ^ @ FtG { bad bad 0 }
    }
    // adapters first (stable ids for the optimizer)
    : Rng rg ( rng_seed seed )
    : ~ i L 0
    ~ < L . m n_layer {
        : i s7 * L 7
        ( __ft_lora_pair tp rg H r * NH hd pids + s7 0 )
        ( __ft_lora_pair tp rg H r * NKV hd pids + s7 1 )
        ( __ft_lora_pair tp rg H r * NKV hd pids + s7 2 )
        ( __ft_lora_pair tp rg * NH hd r H pids + s7 3 )
        ( __ft_lora_pair tp rg H r . m n_ff pids + s7 4 )
        ( __ft_lora_pair tp rg H r . m n_ff pids + s7 5 )
        ( __ft_lora_pair tp rg . m n_ff r H pids + s7 6 )
        = L + L 1
    }
    ( rng_free rg )
    // shared consts
    : ( Vec f ) xrows ( ft_embed m ids )
    : ~ GVar x ( __ft_const tp xrows T2 H )
    ( vec_free [f] xrows )
    : GVar onesH ( __ft_ones tp H )
    : GVar onesF ( __ft_ones tp . m n_ff )
    : GVar onesV ( __ft_ones tp . m n_vocab )
    : i half / hd 2
    : ( Vec f ) cv ( vec_with_cap [f] * T2 half )
    : ( Vec f ) sv ( vec_with_cap [f] * T2 half )
    : ~ i t 0
    ~ < t T2 {
        : ~ i j 0
        ~ < j half {
            : f fr ( pow . m rope_base / * -2.0 # f j # f hd )
            : f ang * # f t fr
            ( vec_push [f] cv ( float_cos ang ) )
            ( vec_push [f] sv ( float_sin ang ) )
            = j + j 1
        }
        = t + t 1
    }
    : GVar Cos ( __ft_const tp cv T2 half )
    : GVar Sin ( __ft_const tp sv T2 half )
    ( vec_free [f] cv ) ( vec_free [f] sv )
    : ( Vec f ) mv ( vec_with_cap [f] * T2 T2 )
    = t 0
    ~ < t T2 {
        : ~ i u 0
        ~ < u T2 { ( vec_push [f] mv ? > u t -1000000000.0 0.0 ) = u + u 1 }
        = t + t 1
    }
    : GVar Mask ( __ft_const tp mv T2 T2 )
    ( vec_free [f] mv )
    : f iscale / 1.0 ( float_sqrt # f hd )

    = L 0
    ~ < L . m n_layer {
        : i s7 * L 7
        : FtW qw ?? ( vec_get [FtW] . m wq L ) { T w → w F → @ FtW { 0 0 ( vec_new [f] ) } }
        : FtW kw ?? ( vec_get [FtW] . m wk L ) { T w → w F → @ FtW { 0 0 ( vec_new [f] ) } }
        : FtW vw ?? ( vec_get [FtW] . m wv L ) { T w → w F → @ FtW { 0 0 ( vec_new [f] ) } }
        : FtW ow ?? ( vec_get [FtW] . m wo L ) { T w → w F → @ FtW { 0 0 ( vec_new [f] ) } }
        : FtW gw ?? ( vec_get [FtW] . m wg L ) { T w → w F → @ FtW { 0 0 ( vec_new [f] ) } }
        : FtW uw ?? ( vec_get [FtW] . m wu L ) { T w → w F → @ FtW { 0 0 ( vec_new [f] ) } }
        : FtW dw ?? ( vec_get [FtW] . m wd L ) { T w → w F → @ FtW { 0 0 ( vec_new [f] ) } }
        : GVar Wq ( __ft_const tp . qw data . qw rows . qw cols )
        : GVar Wk ( __ft_const tp . kw data . kw rows . kw cols )
        : GVar Wv ( __ft_const tp . vw data . vw rows . vw cols )
        : GVar Wo ( __ft_const tp . ow data . ow rows . ow cols )
        : GVar Wg ( __ft_const tp . gw data . gw rows . gw cols )
        : GVar Wu ( __ft_const tp . uw data . uw rows . uw cols )
        : GVar Wd ( __ft_const tp . dw data . dw rows . dw cols )
        : s anp ?? ( vec_get [s] . m an L ) { T x → x F → # s 0 }
        : *FtV anv # *FtV anp
        : GVar N1 ( __ft_const tp . anv v 0 H )
        : s fnp ?? ( vec_get [s] . m fn L ) { T x → x F → # s 0 }
        : *FtV fnv # *FtV fnp
        : GVar N2 ( __ft_const tp . fnv v 0 H )
        // attention
        : GVar xn ( __ft_rms tp x N1 onesH H . m eps )
        : ~ GVar q ( __ft_lora_lin tp xn Wq pids + s7 0 scale )
        : ~ GVar kk ( __ft_lora_lin tp xn Wk pids + s7 1 scale )
        : ~ GVar vv ( __ft_lora_lin tp xn Wv pids + s7 2 scale )
        : s bqp ?? ( vec_get [s] . m bq L ) { T x → x F → # s 0 }
        ? != # i bqp 0 {
            : *FtV bqv # *FtV bqp
            = q ( g_add tp q ( __ft_const tp . bqv v 0 * NH hd ) )
        } {}
        : s bkp ?? ( vec_get [s] . m bk L ) { T x → x F → # s 0 }
        ? != # i bkp 0 {
            : *FtV bkv # *FtV bkp
            = kk ( g_add tp kk ( __ft_const tp . bkv v 0 * NKV hd ) )
        } {}
        : s bvp ?? ( vec_get [s] . m bv L ) { T x → x F → # s 0 }
        ? != # i bvp 0 {
            : *FtV bvv # *FtV bvp
            = vv ( g_add tp vv ( __ft_const tp . bvv v 0 * NKV hd ) )
        } {}
        : ~ GVar ctx @ GVar { -1 }
        : ~ i hI 0
        ~ < hI NH {
            : i kvi / hI / NH NKV
            : GVar qh ( __ft_rope tp ( __ft_headslice tp q T2 * hI hd hd ) Cos Sin T2 hd )
            : GVar kh ( __ft_rope tp ( __ft_headslice tp kk T2 * kvi hd hd ) Cos Sin T2 hd )
            : GVar vh ( __ft_headslice tp vv T2 * kvi hd hd )
            : GVar sc ( g_muls tp ( g_matmul tp qh ( g_transpose tp kh ) ) iscale )
            : GVar aw ( g_softmax tp ( g_add tp sc Mask ) 1 )
            : GVar ch ( g_matmul tp aw vh )
            ? < . ctx id 0 { = ctx ch } { = ctx ( g_concat tp ctx ch 1 ) }
            = hI + hI 1
        }
        : GVar attn ( __ft_lora_lin tp ctx Wo pids + s7 3 scale )
        : GVar x1 ( g_add tp x attn )
        // mlp
        : GVar x1n ( __ft_rms tp x1 N2 onesH H . m eps )
        : GVar gate ( __ft_lora_lin tp x1n Wg pids + s7 4 scale )
        : GVar up ( __ft_lora_lin tp x1n Wu pids + s7 5 scale )
        : GVar act ( g_mul tp ( g_mul tp gate ( g_sigmoid tp gate ) ) up )
        : GVar down ( __ft_lora_lin tp act Wd pids + s7 6 scale )
        = x ( g_add tp x1 down )
        = L + L 1
    }
    : GVar NF ( __ft_const tp . m norm_f 0 H )
    : GVar xf ( __ft_rms tp x NF onesH H . m eps )
    : FtW wo2 . m wout
    : GVar WOUT ( __ft_const tp . wo2 data . wo2 rows . wo2 cols )
    : GVar logits ( g_matmul tp xf WOUT )
    // next-token CE over rows 0..T-2: one-hot [T,V] with row t = ids[t+1]
    // (the last row is all-zero — its softmax pick is masked out of the
    // mean by slicing the picked column to the first T-1 rows).
    : ( Vec f ) oh ( vec_with_cap [f] * T2 . m n_vocab )
    = t 0
    ~ < t T2 {
        : i tgt ? < t - T2 1 ( _ti ids + t 1 ) -1
        : ~ i u 0
        ~ < u . m n_vocab { ( vec_push [f] oh ? == u tgt 1.0 0.0 ) = u + u 1 }
        = t + t 1
    }
    : GVar Oh ( __ft_const tp oh T2 . m n_vocab )
    ( vec_free [f] oh )
    : GVar probs ( g_softmax tp logits 1 )
    : GVar picked ( g_matmul tp ( g_mul tp probs Oh ) onesV )  // [T,1]
    : ( Vec i ) st ( vec_new [i] )
    ( vec_push [i] st 0 ) ( vec_push [i] st 0 )
    : ( Vec i ) sp ( vec_new [i] )
    ( vec_push [i] sp - T2 1 ) ( vec_push [i] sp 1 )
    : GVar pick2 ( g_slice tp picked st sp )
    ( vec_free [i] st ) ( vec_free [i] sp )
    : GVar loss ( g_neg tp ( g_mean tp ( g_log tp pick2 ) ) )
    ^ @ FtG { loss logits * 7 . m n_layer }
}

// ── training driver + adapter I/O + merge ────────────────────────────

// One trained run's result: per-slot adapter values, flat in slot order
// (slot = layer·7 + {q k v o gate up down}); A blocks then B blocks.
: FtTrain {
    b ok
    f l0
    f l1
    ( Vec f ) aflat
    ( Vec f ) bflat
}

@ ft_train_free FtTrain t → v {
    ( vec_free [f] . t aflat )
    ( vec_free [f] . t bflat )
}

@ __ft_ain * FtModel m i slot → i {
    : i w % slot 7
    ? == w 3 { ^ * . m n_head . m head_dim } {}
    ? == w 6 { ^ . m n_ff } {}
    ^ . m n_embd
}

@ __ft_aout * FtModel m i slot → i {
    : i w % slot 7
    ? == w 0 { ^ * . m n_head . m head_dim } {}
    ? | == w 1 == w 2 { ^ * . m n_kv . m head_dim } {}
    ? == w 3 { ^ . m n_embd } {}
    ? | == w 4 == w 5 { ^ . m n_ff } {}
    ^ . m n_embd
}

// Build, capture, train `steps` of device Adam, download the adapters.
@ ft_train * FtModel m ( Vec i ) ids i r f alpha i seed i steps f lr b verbose → FtTrain {
    : i nslot * 7 . m n_layer
    : *u pids ( nurl_alloc * * 2 nslot 8 )
    : *GTape tp ( tape_new )
    : FtG fg ( ft_graph m tp ids r alpha seed pids )
    : ( Vec f ) aflat ( vec_new [f] )
    : ( Vec f ) bflat ( vec_new [f] )
    ? ( tape_ok tp ) {} {
        ( nurl_free pids ) ( tape_free tp )
        ^ @ FtTrain { F 0.0 0.0 aflat bflat }
    }
    : *GpuKit kit ( gk_open 0 )
    : ~ b ok ( gk_ok kit )
    : ~ f l0 0.0
    : ~ f l1 0.0
    ? ok {
        : *GProg pg ( gput_capture kit tp . fg loss )
        = ok ( gput_ok pg )
        : *GpOpt go ( gpopt_adam_new lr )
        : ~ i pi 0
        ~ < pi * 2 nslot {
            ( gpopt_add go pg @ GVar { ( nurl_peek pids pi ) } 0.0 )
            = pi + pi 1
        }
        : ~ i st 0
        ~ & < st steps ok {
            = ok & ok ( gput_forward pg )
            = ok & ok ( gput_backward pg )
            : f lc ( gput_loss pg )
            ? == st 0 { = l0 lc } {}
            ? == st - steps 1 { = l1 lc } {}
            ? & verbose == % st 10 0 {
                ( nurl_print `step ` ) ( nurl_print ( nurl_str_int st ) )
                ( nurl_print ` loss ` ) ( nurl_print ( nurl_str_float lc ) )
                ( nurl_print `\n` )
            } {}
            = ok & ok ( gpopt_step go pg )
            = st + st 1
        }
        = ok & ok ( gput_param_sync_host pg tp )
        ( gpopt_free go )
        ( gput_free pg )
    } {}
    ( gk_close kit )
    // download the trained values from the tape
    : ~ i sl 0
    ~ < sl nslot {
        : GVar pa @ GVar { ( nurl_peek pids * sl 2 ) }
        : GVar pb @ GVar { ( nurl_peek pids + * sl 2 1 ) }
        : Tensor ta ( gvar_value tp pa )
        : Tensor tb ( gvar_value tp pb )
        : ~ i k 0
        ~ < k ( vec_len [f] . ta data ) { ( vec_push [f] aflat ( _tf . ta data k ) ) = k + k 1 }
        = k 0
        ~ < k ( vec_len [f] . tb data ) { ( vec_push [f] bflat ( _tf . tb data k ) ) = k + k 1 }
        = sl + sl 1
    }
    ( nurl_free pids )
    ( tape_free tp )
    ^ @ FtTrain { ok l0 l1 aflat bflat }
}

// ── a minimal safetensors emitter (JSON header + raw LE data) ────────

: StOut {
    String hdr
    ( Vec u ) data
    b first
}

@ __sto_new → StOut { ^ @ StOut { ( string_from `{` ) ( vec_new [u] ) T } }

// Append one F32 tensor (values given as f64, rounded on write).
@ __sto_f32 StOut o s name ( Vec f ) v i d0 i d1 → StOut {
    : ~ StOut so o
    ? . so first { = . so first F } { ( string_push_str . so hdr `,` ) }
    : i at ( vec_len [u] . so data )
    : ~ i k 0
    ~ < k ( vec_len [f] v ) {
        ( bytes_push_f32_le . so data # f32 ( _tf v k ) )
        = k + k 1
    }
    ( string_push_str . so hdr `"` )
    ( string_push_str . so hdr name )
    ( string_push_str . so hdr `":{"dtype":"F32","shape":[` )
    ( string_push_str . so hdr ( nurl_str_int d0 ) )
    ? > d1 0 {
        ( string_push_str . so hdr `,` )
        ( string_push_str . so hdr ( nurl_str_int d1 ) )
    } {}
    ( string_push_str . so hdr `],"data_offsets":[` )
    ( string_push_str . so hdr ( nurl_str_int at ) )
    ( string_push_str . so hdr `,` )
    ( string_push_str . so hdr ( nurl_str_int ( vec_len [u] . so data ) ) )
    ( string_push_str . so hdr `]}` )
    ^ so
}

@ __sto_write StOut o s path → !v String {
    : ~ StOut so o
    ( string_push_str . so hdr `}` )
    : ( Vec u ) out ( vec_new [u] )
    ( bytes_push_u64_le out # u64 ( string_len . so hdr ) )
    : ~ i k 0
    ~ < k ( string_len . so hdr ) {
        ( vec_push [u] out ( nurl_str_get ( string_data . so hdr ) k ) )
        = k + k 1
    }
    = k 0
    ~ < k ( vec_len [u] . so data ) {
        ( vec_push [u] out ?? ( vec_get [u] . so data k ) { T x → x F → # u 0 } )
        = k + k 1
    }
    : ~ b wok T
    ?? ( write_file_bytes path out ) {
        T _ → {}
        F _ → { = wok F }
    }
    ( vec_free [u] out )
    ( string_free . so hdr )
    ( vec_free [u] . so data )
    ? wok { ^ @ !v String { T } }
    ^ @ !v String { F ( string_from `finetune: cannot write file` ) }
}

// Save trained adapters as a safetensors file: per slot,
// blk.<L>.<which>.lora_a [in,r] and .lora_b [r,out], F32.
@ ft_adapters_save s path * FtModel m FtTrain t i r → !v String {
    : ~ StOut so ( __sto_new )
    : i nslot * 7 . m n_layer
    : ~ i sl 0
    : ~ i aoff 0
    : ~ i boff 0
    ~ < sl nslot {
        : i in ( __ft_ain m sl )
        : i out ( __ft_aout m sl )
        : i L / sl 7
        : i w % sl 7
        : ~ s wn `q`
        ? == w 1 { = wn `k` } {}
        ? == w 2 { = wn `v` } {}
        ? == w 3 { = wn `o` } {}
        ? == w 4 { = wn `gate` } {}
        ? == w 5 { = wn `up` } {}
        ? == w 6 { = wn `down` } {}
        : String na ( string_from `blk.` )
        ( string_push_str na ( nurl_str_int L ) )
        ( string_push_str na `.` )
        ( string_push_str na wn )
        : String nb ( string_from ( string_data na ) )
        ( string_push_str na `.lora_a` )
        ( string_push_str nb `.lora_b` )
        : ( Vec f ) av ( vec_with_cap [f] * in r )
        : ~ i k 0
        ~ < k * in r { ( vec_push [f] av ( _tf . t aflat + aoff k ) ) = k + k 1 }
        = so ( __sto_f32 so ( string_data na ) av in r )
        ( vec_free [f] av )
        : ( Vec f ) bv ( vec_with_cap [f] * r out )
        = k 0
        ~ < k * r out { ( vec_push [f] bv ( _tf . t bflat + boff k ) ) = k + k 1 }
        = so ( __sto_f32 so ( string_data nb ) bv r out )
        ( vec_free [f] bv )
        ( string_free na ) ( string_free nb )
        = aoff + aoff * in r
        = boff + boff * r out
        = sl + sl 1
    }
    ^ ( __sto_write so path )
}

// ── merge: base + (α/r)·A·B → a full-weights safetensors file ────────
// nurllama's verified `--weights` path (llm_open_st) then runs the merged
// model with the GGUF supplying metadata + tokenizer. Weights are emitted
// [out, in] F32 under HF names; for NORM-rope models the q/k columns are
// RE-permuted back to the interleaved layout the arch's rope kernel
// expects (the loader's inverse).

// merged tape-layout [in,out] → emit [out,in] rows; q/k: NORM re-permute.
@ __ft_emit_w StOut so s name FtW w b reperm i heads i hd → StOut {
    : i in . w rows
    : i out . w cols
    : ( Vec f ) e ( vec_with_cap [f] * out in )
    : ~ i k 0
    ~ < k * out in { ( vec_push [f] e 0.0 ) = k + k 1 }
    : i half / hd 2
    : ~ i o 0
    ~ < o out {
        // source column in the (possibly half-split) tape layout
        : ~ i src o
        ? reperm {
            : i h / o hd
            : i j % o hd
            ? == % j 2 0 { = src + * h hd / j 2 } { = src + * h hd + half / j 2 }
        } {}
        : ~ i i2 0
        ~ < i2 in {
            ( vec_set [f] e + * o in i2 ( _tf . w data + * i2 out src ) )
            = i2 + i2 1
        }
        = o + o 1
    }
    : StOut so2 ( __sto_f32 so name e out in )
    ( vec_free [f] e )
    ^ so2
}

// Merge every adapter into its base weight and write the FULL model as a
// safetensors file — run it with nurllama's --weights path (llm_open_st).
@ ft_merge_st s path * FtModel m FtTrain t i r f alpha → !v String {
    ^ ( ft_merge_st_mask path m t r alpha 7 )
}

// mask bit0 = embeddings, bit1 = attention projections, bit2 = mlp
// projections (a bisect handle for the merged-path diagnostics).
@ ft_merge_st_mask s path * FtModel m FtTrain t i r f alpha i mask → !v String {
    : f scale / alpha # f r
    : ~ StOut so ( __sto_new )
    // embeddings + final norm (frozen; [V,H] is already [out,in])
    ? == % mask 2 1 {
        = so ( __sto_f32 so `model.embed_tokens.weight` . m embd . m n_vocab . m n_embd )
        = so ( __sto_f32 so `model.norm.weight` . m norm_f . m n_embd 0 )
    } {}
    : i nslot * 7 . m n_layer
    : ~ i sl 0
    : ~ i aoff 0
    : ~ i boff 0
    ~ < sl nslot {
        : i L / sl 7
        : i w % sl 7
        : i in ( __ft_ain m sl )
        : i out ( __ft_aout m sl )
        // the per-layer norms, once per layer (at slot 0)
        ? == w 0 {
            : s anp ?? ( vec_get [s] . m an L ) { T x → x F → # s 0 }
            : *FtV anv # *FtV anp
            : String n1 ( string_from `model.layers.` )
            ( string_push_str n1 ( nurl_str_int L ) )
            ( string_push_str n1 `.input_layernorm.weight` )
            = so ( __sto_f32 so ( string_data n1 ) . anv v . m n_embd 0 )
            ( string_free n1 )
            : s fnp ?? ( vec_get [s] . m fn L ) { T x → x F → # s 0 }
            : *FtV fnv # *FtV fnp
            : String n2 ( string_from `model.layers.` )
            ( string_push_str n2 ( nurl_str_int L ) )
            ( string_push_str n2 `.post_attention_layernorm.weight` )
            = so ( __sto_f32 so ( string_data n2 ) . fnv v . m n_embd 0 )
            ( string_free n2 )
        } {}
        : ~ FtW w0 @ FtW { 0 0 ( vec_new [f] ) }
        ? == w 0 { = w0 ?? ( vec_get [FtW] . m wq L ) { T x → x F → w0 } } {}
        ? == w 1 { = w0 ?? ( vec_get [FtW] . m wk L ) { T x → x F → w0 } } {}
        ? == w 2 { = w0 ?? ( vec_get [FtW] . m wv L ) { T x → x F → w0 } } {}
        ? == w 3 { = w0 ?? ( vec_get [FtW] . m wo L ) { T x → x F → w0 } } {}
        ? == w 4 { = w0 ?? ( vec_get [FtW] . m wg L ) { T x → x F → w0 } } {}
        ? == w 5 { = w0 ?? ( vec_get [FtW] . m wu L ) { T x → x F → w0 } } {}
        ? == w 6 { = w0 ?? ( vec_get [FtW] . m wd L ) { T x → x F → w0 } } {}
        // merged = W0 + scale·A·B, in tape layout [in,out]
        : ( Vec f ) md ( vec_with_cap [f] * in out )
        : ~ i i2 0
        ~ < i2 in {
            : ~ i o 0
            ~ < o out {
                : ~ f acc 0.0
                : ~ i k 0
                ~ < k r {
                    = acc + acc * ( _tf . t aflat + aoff + * i2 r k ) ( _tf . t bflat + boff + * k out o )
                    = k + k 1
                }
                ( vec_push [f] md + ( _tf . w0 data + * i2 out o ) * scale acc )
                = o + o 1
            }
            = i2 + i2 1
        }
        : FtW mw @ FtW { in out md }
        : ~ s pn `self_attn.q_proj.weight`
        ? == w 1 { = pn `self_attn.k_proj.weight` } {}
        ? == w 2 { = pn `self_attn.v_proj.weight` } {}
        ? == w 3 { = pn `self_attn.o_proj.weight` } {}
        ? == w 4 { = pn `mlp.gate_proj.weight` } {}
        ? == w 5 { = pn `mlp.up_proj.weight` } {}
        ? == w 6 { = pn `mlp.down_proj.weight` } {}
        : String nm ( string_from `model.layers.` )
        ( string_push_str nm ( nurl_str_int L ) )
        ( string_push_str nm `.` )
        ( string_push_str nm pn )
        : b reperm & == . m rope_style 0 | == w 0 == w 1
        : i heads ? == w 0 . m n_head . m n_kv
        : b want ? <= w 3 == % / mask 2 2 1 == % / mask 4 2 1
        ? want { = so ( __ft_emit_w so ( string_data nm ) mw reperm heads . m head_dim ) } {}
        ( string_free nm )
        ( vec_free [f] md )
        // qwen2 q/k/v biases pass through unmerged (NEOX: no reperm)
        ? <= w 2 {
            : ~ s bp # s 0
            ? == w 0 { = bp ?? ( vec_get [s] . m bq L ) { T x → x F → # s 0 } } {}
            ? == w 1 { = bp ?? ( vec_get [s] . m bk L ) { T x → x F → # s 0 } } {}
            ? == w 2 { = bp ?? ( vec_get [s] . m bv L ) { T x → x F → # s 0 } } {}
            ? != # i bp 0 {
                : *FtV bv2 # *FtV bp
                : ~ s bn `self_attn.q_proj.bias`
                ? == w 1 { = bn `self_attn.k_proj.bias` } {}
                ? == w 2 { = bn `self_attn.v_proj.bias` } {}
                : String nb ( string_from `model.layers.` )
                ( string_push_str nb ( nurl_str_int L ) )
                ( string_push_str nb `.` )
                ( string_push_str nb bn )
                = so ( __sto_f32 so ( string_data nb ) . bv2 v out 0 )
                ( string_free nb )
            } {}
        } {}
        = aoff + aoff * in r
        = boff + boff * r out
        = sl + sl 1
    }
    ^ ( __sto_write so path )
}
