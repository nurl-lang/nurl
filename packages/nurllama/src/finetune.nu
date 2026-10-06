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
// Architectures: llama-family, qwen2 (bias'd q/k/v, NEOX rope) and qwen3
// (no biases, NEOX rope, per-head Q/K RMSNorm before the rotation). The
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
$ `deps/nn/src/nn.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `deps/safetensor/src/write.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `tokenizer.nu`
$ `stdlib/core/rcbox.nu`

// An optional per-layer 1-D tensor (norm weight / bias): `has` says
// whether the model carries it (llama has no attn_q_norm), `v` holds its
// values (empty for a shape-only placeholder).
: FtV {
    b has
    ( Vec f ) v
}

@ __ft_nov → FtV { ^ @ FtV { F ( vec_new [f] ) } }

// One weight in tape layout: data [rows=in, cols=out] flat.
: FtW {
    i rows
    i cols
    ( Vec f ) data
}

: FtModelImpl {
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
    ( Vec FtV ) bq ( Vec FtV ) bk ( Vec FtV ) bv  // qwen2's biases (absent elsewhere)
    ( Vec FtV ) an ( Vec FtV ) fn  // attn_norm / ffn_norm per layer
    // qwen3's per-head Q/K RMSNorm weights [head_dim]. Absent for
    // llama/qwen2 — an absent one simply skips the norm.
    ( Vec FtV ) qn ( Vec FtV ) kn
    String src_path  // the GGUF path — so the per-layer base matrices can be
    // freed after device capture (ft_drop_base) and streamed back for the
    // merge (ft_reload_base), keeping host RAM off the base during training
    // STREAMING mode (ft_set_stream). The base weights are never all resident
    // host-side: ft_open reads their SHAPES only, ft_graph declares them as
    // lazy consts, and ft_stream_upload fills each one straight into its
    // device buffer after the capture, freeing it again before the next.
    // Host peak becomes one layer instead of the whole model — the
    // difference between training a 4B model on a 31 GB box and not.
    b stream
    ( Vec i ) lz_node  // tape node id of each lazy base const
    ( Vec i ) lz_key  // its identity: layer * 16 + slot (__ft_base_name)
    Gguf mgg  // a Gguf held open across a streamed merge (gguf_none = none)
}

// An FtModel is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: FtModel { s ctl }

unsafe @ FtModel_share FtModel h → FtModel { ^ @ FtModel { # s ( rcbox_share # i . h ctl ) } }

@ FtModel_drop sink FtModel h → v {
    ( mem_forget h )
    ( rcbox_release [FtModelImpl] # i . h ctl )
}

unsafe @ __FtModel_ptr FtModel h → *FtModelImpl { ^ ( rcbox_ptr [FtModelImpl] # i . h ctl ) }

// Streaming base upload, OFF by default: the finetune tests compare the CPU
// tape's loss against the device's, and a lazy const has no host values to
// compare with. `nurllama finetune --stream` turns it on for models whose
// f64 host copy would not fit.
: ~ b __ft_stream_on F

@ ft_set_stream b on → v { = __ft_stream_on on }

@ __ft_stream_wanted → b { ^ __ft_stream_on }

// Let go of `m` now rather than at the end of its owner's scope.
@ ft_free sink FtModel m → v {}

// Dequant tensor `name` to f64. GGUF layout [out, in] flat (in fastest).
@ __ft_raw Gguf gg s name inout i rows inout i cols → ( Vec f ) {
    : i idx ( gguf_find_tensor gg name )
    ? >= idx 0 {} { ^ ( vec_new [f] ) }
    : GgufTensor t ?? ( vec_get [GgufTensor] ( gguf_tensors gg ) idx ) {
        T x → x
        F → @ GgufTensor { ( string_new ) 0 0 0 0 0 0 0 0 0 }
    }
    ?? ( gguf_dequant_f64 gg idx ) {
        T v → {
            = rows . t d1  // out
            = cols . t d0  // in
            ^ v
        }
        F e → {
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
@ __ft_unperm FtW w i heads i hd → v { ( __ft_unperm_data . w data . w rows . w cols heads hd ) }

@ __ft_unperm_data ( Vec f ) data i rows i cols i heads i hd → v {
    : i half / hd 2
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
                ( vec_set [f] tmp + * h hd j ( _tf data + base + * h hd * 2 j ) )
                ( vec_set [f] tmp + * h hd + half j ( _tf data + base + * h hd + * 2 j 1 ) )
                = j + j 1
            }
            = h + h 1
        }
        = c 0
        ~ < c cols { ( vec_set [f] data + base c ( _tf tmp c ) ) = c + c 1 }
        = r + r 1
    }
}

// Same un-permutation for a bias vector (one row).
@ __ft_unperm_vec FtV p i heads i hd → v { ( __ft_unperm_data . p v 1 * heads hd heads hd ) }

@ __ft_lname i layer s suffix → String {
    : String s ( string_from `blk.` )
    ( string_push_str s ( nurl_str_int layer ) )
    ( string_push_str s `.` )
    ( string_push_str s suffix )
    ^ s
}

// The tape-layout SHAPE of a layer weight, read from the GGUF's tensor
// table without touching a byte of its data. Rows/cols mirror __ft_raw +
// __ft_transpose exactly: rows = d0 (in), cols = d1 (out). An absent tensor
// gives 0×0, which callers read as "not present".
@ __ft_lshape Gguf gg i layer s suffix inout i rows inout i cols → v {
    = rows 0
    = cols 0
    : String nm ( __ft_lname layer suffix )
    : i idx ( gguf_find_tensor gg ( string_data nm ) )
    ? >= idx 0 {} { ^ v }
    ?? ( vec_get [GgufTensor] ( gguf_tensors gg ) idx ) {
        T t → {
            = rows . t d0
            = cols . t d1
        }
        F → {}
    }
}

// A layer weight in tape layout (clears `ok` on a missing tensor).
@ __ft_lw Gguf gg i layer s suffix inout b ok → FtW {
    : String nm ( __ft_lname layer suffix )
    : ~ i rows 0
    : ~ i cols 0
    : ( Vec f ) raw ( __ft_raw gg ( string_data nm ) rows cols )
    ? > ( vec_len [f] raw ) 0 {} {
        = ok F
        ^ @ FtW { 0 0 ( vec_new [f] ) }
    }
    ^ ( __ft_transpose raw rows cols )
}

// An optional 1-D tensor (norm weight / bias); absent when the model
// does not carry it.
@ __ft_lvec Gguf gg i layer s suffix → FtV {
    : String nm ( __ft_lname layer suffix )
    : ~ i rows 0
    : ~ i cols 0
    : ( Vec f ) raw ( __ft_raw gg ( string_data nm ) rows cols )
    ? > ( vec_len [f] raw ) 0 {} { ^ ( __ft_nov ) }
    ^ @ FtV { T raw }
}

// Open a GGUF and lift every weight into tape-ready f64 host tensors.
// Load every per-layer base matrix (q/k/v/o + gate/up/down) and the biases
// / norms into `m`'s (already-created) vecs, un-permuting NORM-rope q/k the
// same way whether called at open or at merge-time reload. `gg` stays the
// caller's to close. Poisons m.ok on a missing tensor.
// One shape-only per-layer weight: real rows/cols, no data.
@ __ft_shape_push Gguf gg i L s suffix ( Vec FtW ) dst → v {
    : ~ i rows 0
    : ~ i cols 0
    ( __ft_lshape gg L suffix rows cols )
    ( vec_push [FtW] dst @ FtW { rows cols ( vec_new [f] ) } )
}

// One shape-only per-layer 1-D tensor: present with no values when the
// model HAS this tensor, absent when it does not (llama has no attn_q_norm).
@ __ft_shape_vec Gguf gg i L s suffix ( Vec FtV ) dst → v {
    : String nm ( __ft_lname L suffix )
    : i idx ( gguf_find_tensor gg ( string_data nm ) )
    ( vec_push [FtV] dst @ FtV { >= idx 0 ( vec_new [f] ) } )
}

// The streaming counterpart of __ft_load_bases: read every per-layer
// SHAPE and no data at all. ft_graph turns each into a lazy const and
// ft_stream_upload fills them one at a time after the capture.
unsafe @ __ft_load_shapes Gguf gg * FtModelImpl m → v {
    = . m n_ff 0
    : ~ i L 0
    ~ < L . m n_layer {
        ( __ft_shape_push gg L `attn_q.weight` . m wq )
        ( __ft_shape_push gg L `attn_k.weight` . m wk )
        ( __ft_shape_push gg L `attn_v.weight` . m wv )
        ( __ft_shape_push gg L `attn_output.weight` . m wo )
        ( __ft_shape_push gg L `ffn_gate.weight` . m wg )
        ? == . m n_ff 0 {
            ?? ( vec_get [FtW] . m wg L ) { T w → { = . m n_ff . w cols } F → {} }
        } {}
        ( __ft_shape_push gg L `ffn_up.weight` . m wu )
        ( __ft_shape_push gg L `ffn_down.weight` . m wd )
        ( __ft_shape_vec gg L `attn_q.bias` . m bq )
        ( __ft_shape_vec gg L `attn_k.bias` . m bk )
        ( __ft_shape_vec gg L `attn_v.bias` . m bv )
        ( __ft_shape_vec gg L `attn_norm.weight` . m an )
        ( __ft_shape_vec gg L `ffn_norm.weight` . m fn )
        ( __ft_shape_vec gg L `attn_q_norm.weight` . m qn )
        ( __ft_shape_vec gg L `attn_k_norm.weight` . m kn )
        = L + L 1
    }
    ? > . m n_ff 0 {} { = . m ok F }
}

unsafe @ __ft_load_bases Gguf gg * FtModelImpl m → v {
    ? . m stream { ( __ft_load_shapes gg m ) ^ v } {}
    : ~ b ok T
    // ffn size read from the first gate tensor
    = . m n_ff 0
    : ~ i L 0
    ~ < L . m n_layer {
        : FtW q ( __ft_lw gg L `attn_q.weight` ok )
        : FtW k2 ( __ft_lw gg L `attn_k.weight` ok )
        ? == . m rope_style 0 {
            ( __ft_unperm q . m n_head . m head_dim )
            ( __ft_unperm k2 . m n_kv . m head_dim )
        } {}
        ( vec_push [FtW] . m wq q )
        ( vec_push [FtW] . m wk k2 )
        ( vec_push [FtW] . m wv ( __ft_lw gg L `attn_v.weight` ok ) )
        ( vec_push [FtW] . m wo ( __ft_lw gg L `attn_output.weight` ok ) )
        : FtW g2 ( __ft_lw gg L `ffn_gate.weight` ok )
        ? == . m n_ff 0 { = . m n_ff . g2 cols } {}
        ( vec_push [FtW] . m wg g2 )
        ( vec_push [FtW] . m wu ( __ft_lw gg L `ffn_up.weight` ok ) )
        ( vec_push [FtW] . m wd ( __ft_lw gg L `ffn_down.weight` ok ) )
        : FtV bqp ( __ft_lvec gg L `attn_q.bias` )
        : FtV bkp ( __ft_lvec gg L `attn_k.bias` )
        ? & == . m rope_style 0 . bqp has { ( __ft_unperm_vec bqp . m n_head . m head_dim ) } {}
        ? & == . m rope_style 0 . bkp has { ( __ft_unperm_vec bkp . m n_kv . m head_dim ) } {}
        ( vec_push [FtV] . m bq bqp )
        ( vec_push [FtV] . m bk bkp )
        ( vec_push [FtV] . m bv ( __ft_lvec gg L `attn_v.bias` ) )
        ( vec_push [FtV] . m an ( __ft_lvec gg L `attn_norm.weight` ) )
        ( vec_push [FtV] . m fn ( __ft_lvec gg L `ffn_norm.weight` ) )
        // qwen3 only; 0 everywhere else. NOT un-permuted for NORM rope:
        // the weight is per-LANE inside a head, and the un-permute
        // reorders lanes, so a NORM-rope model carrying these would need
        // the same reorder — none does (qwen3 is NEOX).
        ( vec_push [FtV] . m qn ( __ft_lvec gg L `attn_q_norm.weight` ) )
        ( vec_push [FtV] . m kn ( __ft_lvec gg L `attn_k_norm.weight` ) )
        = L + L 1
    }
    ? ok {} { = . m ok F }
}

// Drop the per-layer base matrices + biases/norms (the bulk of host RAM),
// emptying their vecs (clearing a vec drops its elements). embd / wout / norm_f are KEPT (embd feeds the
// per-window input recompute; the rest are small). Idempotent — a second
// call over empty vecs is a no-op — and reversible via ft_reload_base.
unsafe @ ft_drop_base FtModel m__h → v {
    : *FtModelImpl m ( __FtModel_ptr m__h )
    ( vec_clear [FtW] . m wq ) ( vec_clear [FtW] . m wk ) ( vec_clear [FtW] . m wv )
    ( vec_clear [FtW] . m wo ) ( vec_clear [FtW] . m wg ) ( vec_clear [FtW] . m wu )
    ( vec_clear [FtW] . m wd )
    ( vec_clear [FtV] . m bq ) ( vec_clear [FtV] . m bk ) ( vec_clear [FtV] . m bv )
    ( vec_clear [FtV] . m an ) ( vec_clear [FtV] . m fn )
    ( vec_clear [FtV] . m qn ) ( vec_clear [FtV] . m kn )
}

// Re-stream the per-layer base from the source GGUF into `m`'s (empty)
// vecs — the reverse of ft_drop_base, using the SAME loader path so the
// NORM-rope un-permute is identical byte-for-byte. Also restores the
// embedding table when ft_merge_st consumed it: training again after a
// merge would otherwise embed every token as a zero row. T on success.
unsafe @ ft_reload_base FtModel m__h → b {
    : *FtModelImpl m ( __FtModel_ptr m__h )
    ?? ( gguf_open ( string_data . m src_path ) ) {
        T gg → {
            ? == ( vec_len [FtW] . m wq ) 0 { ( __ft_load_bases gg m ) } {}
            ? == ( vec_len [f] . m embd ) 0 {
                : ~ i erows 0
                : ~ i ecols 0
                = . m embd ( __ft_raw gg `token_embd.weight` erows ecols )
                ? > ( vec_len [f] . m embd ) 0 {} { = . m ok F }
            } {}
            ^ . m ok
        }
        F e → { ^ F }
    }
    ^ F
}

unsafe @ ft_open s path → !FtModel String {
    ?? ( gguf_open path ) {
        T gg → {
            : s arch ( gguf_kv_str_or gg `general.architecture` `` )
            // zeroed: an early return drops a half-built model cleanly
            : FtModel h @ FtModel { # s ( rcbox_zero [FtModelImpl] ) }
            : *FtModelImpl m ( __FtModel_ptr h )
            = . m ok T
            = . m stream ( __ft_stream_wanted )
            : String kb ( string_from arch )
            ( string_push_str kb `.embedding_length` )
            = . m n_embd ( gguf_kv_int_or gg ( string_data kb ) 0 )
            : String kb2 ( string_from arch )
            ( string_push_str kb2 `.block_count` )
            = . m n_layer ( gguf_kv_int_or gg ( string_data kb2 ) 0 )
            : String kb3 ( string_from arch )
            ( string_push_str kb3 `.attention.head_count` )
            = . m n_head ( gguf_kv_int_or gg ( string_data kb3 ) 0 )
            : String kb4 ( string_from arch )
            ( string_push_str kb4 `.attention.head_count_kv` )
            = . m n_kv ( gguf_kv_int_or gg ( string_data kb4 ) . m n_head )
            : String kb5 ( string_from arch )
            ( string_push_str kb5 `.attention.layer_norm_rms_epsilon` )
            = . m eps ( gguf_kv_f_or gg ( string_data kb5 ) 0.00001 )
            : String kb6 ( string_from arch )
            ( string_push_str kb6 `.rope.freq_base` )
            = . m rope_base ( gguf_kv_f_or gg ( string_data kb6 ) 10000.0 )
            // head_dim is NOT n_embd/n_head in general — qwen3-4B states
            // 128 against a 2560/32 = 80 — so read key_length when the
            // model publishes it. Everything downstream already sizes
            // attention off n_head·head_dim rather than n_embd.
            ? > . m n_head 0 { = . m head_dim / . m n_embd . m n_head } {}
            : String kb8 ( string_from arch )
            ( string_push_str kb8 `.attention.key_length` )
            = . m head_dim ( gguf_kv_int_or gg ( string_data kb8 ) . m head_dim )
            : String kb7 ( string_from arch )
            ( string_push_str kb7 `.rope.dimension_count` )
            = . m rope_dim ( gguf_kv_int_or gg ( string_data kb7 ) . m head_dim )
            // qwen2 and qwen3 both rotate the two halves of the span (NEOX);
            // llama rotates adjacent lanes (NORM, un-permuted at load).
            : b is_q3 != 0 ( nurl_str_eq arch `qwen3` )
            = . m rope_style ? | == ( nurl_str_eq arch `qwen2` ) 1 is_q3 1 0
            ? & > . m n_embd 0 > . m n_layer 0 {} {
                ^ @ !FtModel String { F ( string_from `finetune: not a llama/qwen2/qwen3 GGUF` ) }
            }
            // embeddings [vocab, n_embd]
            : ~ i erows 0
            : ~ i ecols 0
            = . m embd ( __ft_raw gg `token_embd.weight` erows ecols )
            = . m n_vocab erows
            ? > ( vec_len [f] . m embd ) 0 {} { = . m ok F }
            // lm_head: output.weight, or the tied embedding table. Streaming
            // takes its SHAPE only — a 151936 x 2560 f64 transpose is 3.1 GB
            // of host RAM that a device buffer needs for one upload.
            : i oi ( gguf_find_tensor gg `output.weight` )
            ? . m stream {
                = . m wout @ FtW { . m n_embd . m n_vocab ( vec_new [f] ) }
            } {
                ? >= oi 0 {
                    : ~ i orows 0
                    : ~ i ocols 0
                    : ( Vec f ) raw ( __ft_raw gg `output.weight` orows ocols )
                    = . m wout ( __ft_transpose raw orows ocols )
                } {
                    = . m wout ( __ft_transpose . m embd . m n_vocab . m n_embd )
                }
            }
            : ~ i nrows 0
            : ~ i ncols 0
            = . m norm_f ( __ft_raw gg `output_norm.weight` nrows ncols )
            = . m wq ( vec_new [FtW] )
            = . m wk ( vec_new [FtW] )
            = . m wv ( vec_new [FtW] )
            = . m wo ( vec_new [FtW] )
            = . m wg ( vec_new [FtW] )
            = . m wu ( vec_new [FtW] )
            = . m wd ( vec_new [FtW] )
            = . m bq ( vec_new [FtV] )
            = . m bk ( vec_new [FtV] )
            = . m bv ( vec_new [FtV] )
            = . m an ( vec_new [FtV] )
            = . m fn ( vec_new [FtV] )
            = . m qn ( vec_new [FtV] )
            = . m kn ( vec_new [FtV] )
            = . m mgg ( gguf_none )
            = . m lz_node ( vec_new [i] )
            = . m lz_key ( vec_new [i] )
            = . m src_path ( string_from path )
            ( __ft_load_bases gg m )
            ? . m ok {} { ^ @ !FtModel String { F ( string_from `finetune: missing tensors in GGUF` ) } }
            ^ @ !FtModel String { T h }
        }
        F e → { ^ @ !FtModel String { F e } }
    }
}

// The model's shape, for callers that size buffers or print it.
unsafe @ ft_n_embd FtModel h → i { ^ . ( __FtModel_ptr h ) n_embd }

unsafe @ ft_n_layer FtModel h → i { ^ . ( __FtModel_ptr h ) n_layer }

unsafe @ ft_n_head FtModel h → i { ^ . ( __FtModel_ptr h ) n_head }

unsafe @ ft_n_kv FtModel h → i { ^ . ( __FtModel_ptr h ) n_kv }

unsafe @ ft_head_dim FtModel h → i { ^ . ( __FtModel_ptr h ) head_dim }

unsafe @ ft_n_vocab FtModel h → i { ^ . ( __FtModel_ptr h ) n_vocab }

unsafe @ ft_rope_style FtModel h → i { ^ . ( __FtModel_ptr h ) rope_style }

// Whether layer L carries qwen3's per-head Q and K norms (both of them).
unsafe @ ft_has_qk_norm FtModel h i L → b {
    : *FtModelImpl m ( __FtModel_ptr h )
    : b q ?? ( vec_get [FtV] . m qn L ) { T x → . x has F → F }
    : b k ?? ( vec_get [FtV] . m kn L ) { T x → . x has F → F }
    ^ & q k
}

// ── the tape graph ────────────────────────────────────────────────────

// Host-side embedding lookup: token ids → [T, n_embd] rows.
unsafe @ ft_embed FtModel m__h ( Vec i ) ids → ( Vec f ) {
    : *FtModelImpl m ( __FtModel_ptr m__h )
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

@ __ft_const GTape tp ( Vec f ) v i r i c → GVar {
    : ( Vec i ) s ( vec_new [i] )
    ? > r 0 { ( vec_push [i] s r ) } {}
    ( vec_push [i] s c )
    // A shape with no values is a STREAMED base weight: the capture sizes
    // its device buffer from the shape and ft_stream_upload fills it after,
    // so the whole model never sits in host RAM at once.
    : i nel * ? > r 0 r 1 c
    ? & == ( vec_len [f] v ) 0 > nel 0 {
        : GVar g ( grad_const_lazy tp s TE_F64 )
        ^ g
    } {}
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar o ( grad_const tp t )
    ^ o
}

@ __ft_ones GTape tp i n → GVar {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 1.0 ) = k + k 1 }
    : GVar o ( __ft_const tp v n 1 )
    ^ o
}

// Which GGUF tensor a streamed base const streams from. The key packed into
// lz_key is layer * 16 + k, so one definition pairs the graph's consts with
// the loader's tensors — there are not two orderings that must agree.
@ __ft_base_name i k → s {
    ? == k 0 { ^ `attn_norm.weight` } {}
    ? == k 1 { ^ `ffn_norm.weight` } {}
    ? == k 2 { ^ `attn_q.weight` } {}
    ? == k 3 { ^ `attn_k.weight` } {}
    ? == k 4 { ^ `attn_v.weight` } {}
    ? == k 5 { ^ `attn_output.weight` } {}
    ? == k 6 { ^ `ffn_gate.weight` } {}
    ? == k 7 { ^ `ffn_up.weight` } {}
    ? == k 8 { ^ `ffn_down.weight` } {}
    ? == k 9 { ^ `attn_q_norm.weight` } {}
    ? == k 10 { ^ `attn_k_norm.weight` } {}
    ? == k 11 { ^ `attn_q.bias` } {}
    ? == k 12 { ^ `attn_k.bias` } {}
    ? == k 13 { ^ `attn_v.bias` } {}
    ^ ``
}

// Note a streamed base const's tape node so ft_stream_upload can fill it.
unsafe @ __ft_rec * FtModelImpl m GVar g i L i k → GVar {
    ? . m stream {
        ( vec_push [i] . m lz_node . g id )
        ( vec_push [i] . m lz_key + * L 16 k )
    } {}
    ^ g
}

// qwen3: RMSNorm every head's Q (or K) vector before the rotation. The
// projection is [T, heads·head_dim] and the norm runs over head_dim, so
// the rows to normalise are a [T·heads, head_dim] VIEW of the same
// elements — row-major order already lays them out that way, which makes
// this two reshapes around the ordinary rmsnorm. `wp` 0 (llama, qwen2)
// returns the input untouched.
@ __ft_head_norm GTape tp GVar x GVar W b have i T2 i heads i hd GVar ones f eps → GVar {
    ? have {} { ^ x }
    : ( Vec i ) flat_s ( vec_new [i] )
    ( vec_push [i] flat_s * T2 heads )
    ( vec_push [i] flat_s hd )
    : GVar flat ( g_reshape tp x flat_s )
    : GVar normed ( nn_rmsnorm tp flat W ones hd eps )
    : ( Vec i ) back_s ( vec_new [i] )
    ( vec_push [i] back_s T2 )
    ( vec_push [i] back_s * heads hd )
    : GVar o ( g_reshape tp normed back_s )
    ^ o
}

// LoRA pair registration: A [in,r] seeded small, B [r,out] zero.
@ __ft_lora_pair GTape tp Rng rg i in i r i out ( Vec i ) pids i slot → v {
    : ( Vec f ) av ( vec_with_cap [f] * in r )
    : f lim / 1.0 ( float_sqrt # f in )
    : ~ i k 0
    ~ < k * in r { ( vec_push [f] av * lim - * 2.0 ( rng_u01 rg ) 1.0 ) = k + k 1 }
    : ( Vec i ) as2 ( vec_new [i] )
    ( vec_push [i] as2 in ) ( vec_push [i] as2 r )
    : Tensor at ( tensor_from_data TE_F64 as2 av )
    : GVar pa ( grad_param tp at )
    : ( Vec f ) bv ( vec_with_cap [f] * r out )
    = k 0
    ~ < k * r out { ( vec_push [f] bv 0.0 ) = k + k 1 }
    : ( Vec i ) bs ( vec_new [i] )
    ( vec_push [i] bs r ) ( vec_push [i] bs out )
    : Tensor bt ( tensor_from_data TE_F64 bs bv )
    : GVar pb ( grad_param tp bt )
    : b _a ( vec_set [i] pids * slot 2 . pa id )
    : b _b ( vec_set [i] pids + * slot 2 1 . pb id )
}

// LoRA linear over the pids-registered adapter for `slot` (the plumbing;
// the math is nn_lora_linear).
@ __ft_lora_lin GTape tp GVar x GVar w0 ( Vec i ) pids i slot f scale → GVar {
    : GVar pa @ GVar { ( _ti pids * slot 2 ) }
    : GVar pb @ GVar { ( _ti pids + * slot 2 1 ) }
    ^ ( nn_lora_linear tp x w0 pa pb scale )
}

// The result handles of one built graph.
: FtG {
    GVar loss
    GVar logits
    GVar xin  // the input-rows const — refresh per window via gput_set_input
    GVar ohin  // the one-hot target const — refreshed together with xin
    i n_pairs  // LoRA pairs registered (7 per layer)
}

// Build the full forward + next-token CE loss on `tp`. `ids` is one
// sequence (T tokens; loss over positions 0..T-2 predicting 1..T-1).
// `pids` receives the 2·7·n_layer LoRA parameter ids (A, B per slot);
// LoRA params register FIRST.
unsafe @ ft_graph FtModel m__h GTape tp ( Vec i ) ids i r f alpha i seed ( Vec i ) pids → FtG {
    : *FtModelImpl m ( __FtModel_ptr m__h )
    : b _sized ( vec_resize_zeroed [i] pids * 14 . m n_layer )
    : i T2 ( vec_len [i] ids )
    : i H . m n_embd
    : i hd . m head_dim
    : i NH . m n_head
    : i NKV . m n_kv
    : f scale / alpha # f r
    ? == . m rope_dim hd {} {
        : GVar bad ( grad_poison tp `finetune: partial rotary not supported` )
        ^ @ FtG { bad bad bad bad 0 }
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
    // shared consts
    : ( Vec f ) xrows ( ft_embed m__h ids )
    : ~ GVar x ( __ft_const tp xrows T2 H )
    : GVar xin @ GVar { . x id }
    : GVar onesH ( __ft_ones tp H )
    : GVar onesHD ( __ft_ones tp hd )
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
    : ( Vec f ) mv ( vec_with_cap [f] * T2 T2 )
    = t 0
    ~ < t T2 {
        : ~ i u 0
        ~ < u T2 { ( vec_push [f] mv ? > u t -1000000000.0 0.0 ) = u + u 1 }
        = t + t 1
    }
    : GVar Mask ( __ft_const tp mv T2 T2 )
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
        : GVar Wq ( __ft_rec m ( __ft_const tp . qw data . qw rows . qw cols ) L 2 )
        : GVar Wk ( __ft_rec m ( __ft_const tp . kw data . kw rows . kw cols ) L 3 )
        : GVar Wv ( __ft_rec m ( __ft_const tp . vw data . vw rows . vw cols ) L 4 )
        : GVar Wo ( __ft_rec m ( __ft_const tp . ow data . ow rows . ow cols ) L 5 )
        : GVar Wg ( __ft_rec m ( __ft_const tp . gw data . gw rows . gw cols ) L 6 )
        : GVar Wu ( __ft_rec m ( __ft_const tp . uw data . uw rows . uw cols ) L 7 )
        : GVar Wd ( __ft_rec m ( __ft_const tp . dw data . dw rows . dw cols ) L 8 )
        : FtV anv ?? ( vec_get [FtV] . m an L ) { T fv → fv F → ( __ft_nov ) }
        : GVar N1 ( __ft_rec m ( __ft_const tp . anv v 0 H ) L 0 )
        : FtV fnv ?? ( vec_get [FtV] . m fn L ) { T fv → fv F → ( __ft_nov ) }
        : GVar N2 ( __ft_rec m ( __ft_const tp . fnv v 0 H ) L 1 )
        // qwen3's per-head Q/K norms, declared here so every base const of
        // this layer is created in one place (the streamer pairs by key).
        : FtV qnv ?? ( vec_get [FtV] . m qn L ) { T fv → fv F → ( __ft_nov ) }
        : FtV knv ?? ( vec_get [FtV] . m kn L ) { T fv → fv F → ( __ft_nov ) }
        : b haveqn . qnv has
        : b havekn . knv has
        : ~ GVar QN @ GVar { -1 }
        : ~ GVar KN @ GVar { -1 }
        ? haveqn { = QN ( __ft_rec m ( __ft_const tp . qnv v 0 hd ) L 9 ) } {}
        ? havekn { = KN ( __ft_rec m ( __ft_const tp . knv v 0 hd ) L 10 ) } {}
        // attention
        : GVar xn ( nn_rmsnorm tp x N1 onesH H . m eps )
        : ~ GVar q ( __ft_lora_lin tp xn Wq pids + s7 0 scale )
        : ~ GVar kk ( __ft_lora_lin tp xn Wk pids + s7 1 scale )
        : ~ GVar vv ( __ft_lora_lin tp xn Wv pids + s7 2 scale )
        : FtV bqv ?? ( vec_get [FtV] . m bq L ) { T fv → fv F → ( __ft_nov ) }
        ? . bqv has {
            = q ( g_add tp q ( __ft_rec m ( __ft_const tp . bqv v 0 * NH hd ) L 11 ) )
        } {}
        : FtV bkv ?? ( vec_get [FtV] . m bk L ) { T fv → fv F → ( __ft_nov ) }
        ? . bkv has {
            = kk ( g_add tp kk ( __ft_rec m ( __ft_const tp . bkv v 0 * NKV hd ) L 12 ) )
        } {}
        : FtV bvv ?? ( vec_get [FtV] . m bv L ) { T fv → fv F → ( __ft_nov ) }
        ? . bvv has {
            = vv ( g_add tp vv ( __ft_rec m ( __ft_const tp . bvv v 0 * NKV hd ) L 13 ) )
        } {}
        // qwen3 norms every head's Q and K before the rotation; absent
        // weights (llama, qwen2) leave q and kk untouched.
        = q ( __ft_head_norm tp q QN haveqn T2 NH hd onesHD . m eps )
        = kk ( __ft_head_norm tp kk KN havekn T2 NKV hd onesHD . m eps )
        : GVar ctx ( nn_gqa_attention tp q kk vv Cos Sin Mask T2 NH NKV hd iscale )
        : GVar attn ( __ft_lora_lin tp ctx Wo pids + s7 3 scale )
        : GVar x1 ( g_add tp x attn )
        // mlp
        : GVar x1n ( nn_rmsnorm tp x1 N2 onesH H . m eps )
        : GVar gate ( __ft_lora_lin tp x1n Wg pids + s7 4 scale )
        : GVar up ( __ft_lora_lin tp x1n Wu pids + s7 5 scale )
        : GVar act ( g_mul tp ( g_mul tp gate ( g_sigmoid tp gate ) ) up )
        : GVar down ( __ft_lora_lin tp act Wd pids + s7 6 scale )
        = x ( g_add tp x1 down )
        = L + L 1
    }
    : GVar NF ( __ft_const tp . m norm_f 0 H )
    : GVar xf ( nn_rmsnorm tp x NF onesH H . m eps )
    : FtW wo2 . m wout
    : GVar WOUT ( __ft_rec m ( __ft_const tp . wo2 data . wo2 rows . wo2 cols )
    . m n_layer 15 )
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
    : GVar ohin @ GVar { . Oh id }
    // next-token CE over rows 0..T-2 (the last position has no target)
    : GVar loss ( nn_cross_entropy_rows tp logits Oh onesV - T2 1 )
    ^ @ FtG { loss logits xin ohin * 7 . m n_layer }
}

// The one-hot rows for a window's ids (row t = ids[t+1]; last row zero).
unsafe @ ft_onehot FtModel m__h ( Vec i ) ids → ( Vec f ) {
    : *FtModelImpl m ( __FtModel_ptr m__h )
    : i T2 ( vec_len [i] ids )
    : ( Vec f ) oh ( vec_with_cap [f] * T2 . m n_vocab )
    : ~ i t 0
    ~ < t T2 {
        : i tgt ? < t - T2 1 ( _ti ids + t 1 ) -1
        : ~ i u 0
        ~ < u . m n_vocab { ( vec_push [f] oh ? == u tgt 1.0 0.0 ) = u + u 1 }
        = t + t 1
    }
    ^ oh
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

unsafe @ __ft_ain * FtModelImpl m i slot → i {
    : i w % slot 7
    ? == w 3 { ^ * . m n_head . m head_dim } {}
    ? == w 6 { ^ . m n_ff } {}
    ^ . m n_embd
}

unsafe @ __ft_aout * FtModelImpl m i slot → i {
    : i w % slot 7
    ? == w 0 { ^ * . m n_head . m head_dim } {}
    ? | == w 1 == w 2 { ^ * . m n_kv . m head_dim } {}
    ? == w 3 { ^ . m n_embd } {}
    ? | == w 4 == w 5 { ^ . m n_ff } {}
    ^ . m n_embd
}

// Build once from the first window, capture, then train `steps` of device
// Adam ROUND-ROBIN over every `win`-token window of the corpus: the graph
// is static (fixed T), so a window switch is two gput_set_input uploads
// (the embedded rows + the one-hot targets) — no rebuild, no recapture.
// ── streaming the base weights onto the device ────────────────────────
//
// Every value here goes through the SAME loader the eager path uses
// (__ft_lw / __ft_lvec, NORM-rope un-permute included), so a streamed run
// and an eager run upload identical bytes — what changes is only that one
// tensor is resident at a time instead of the whole model.

unsafe @ __ft_up_vec * FtModelImpl m Gguf gg GProg pg i node i L s suf → b {
    : FtV pv ( __ft_lvec gg L suf )
    ? . pv has {} { ^ F }
    ? == . m rope_style 0 {
        ? ( nurl_str_eq suf `attn_q.bias` ) { ( __ft_unperm_vec pv . m n_head . m head_dim ) } {}
        ? ( nurl_str_eq suf `attn_k.bias` ) { ( __ft_unperm_vec pv . m n_kv . m head_dim ) } {}
    } {}
    ^ ( gput_set_input pg @ GVar { node } . pv v )
}

unsafe @ __ft_up_layer * FtModelImpl m Gguf gg GProg pg i node i L i slot → b {
    : s suf ( __ft_base_name slot )
    ? | | | | | | == slot 0 == slot 1 == slot 9 == slot 10 == slot 11 == slot 12 == slot 13 {
        ^ ( __ft_up_vec m gg pg node L suf )
    } {}
    : ~ b lok T
    : FtW w ( __ft_lw gg L suf lok )
    ? lok {} { ^ F }
    ? == . m rope_style 0 {
        ? == slot 2 { ( __ft_unperm w . m n_head . m head_dim ) } {}
        ? == slot 3 { ( __ft_unperm w . m n_kv . m head_dim ) } {}
    } {}
    ^ ( gput_set_input pg @ GVar { node } . w data )
}

unsafe @ __ft_up_wout * FtModelImpl m Gguf gg GProg pg i node → b {
    : i oi ( gguf_find_tensor gg `output.weight` )
    ? >= oi 0 {
        : ~ i rows 0
        : ~ i cols 0
        : ( Vec f ) raw ( __ft_raw gg `output.weight` rows cols )
        : FtW w ( __ft_transpose raw rows cols )
        ^ ( gput_set_input pg @ GVar { node } . w data )
    } {}
    : FtW w2 ( __ft_transpose . m embd . m n_vocab . m n_embd )
    ^ ( gput_set_input pg @ GVar { node } . w2 data )
}

// ── one layer in, one layer out (the streamed merge) ──────────────────
//
// The merge walks the model layer by layer, so it needs exactly one layer
// of base weights resident at a time — the same trade the training path
// makes. These swap a layer's shape-only placeholders for the real tensors
// and back.

// (vec_set drops the slot's old value)
@ __ft_slot_set ( Vec FtW ) v i L sink FtW w → v { : b _s ( vec_set [FtW] v L w ) }

@ __ft_vslot_set ( Vec FtV ) v i L sink FtV p → v { : b _s ( vec_set [FtV] v L p ) }

unsafe @ __ft_layer_in Gguf gg * FtModelImpl m i L → b {
    : ~ b ok T
    : FtW q ( __ft_lw gg L `attn_q.weight` ok )
    : FtW k2 ( __ft_lw gg L `attn_k.weight` ok )
    ? == . m rope_style 0 {
        ( __ft_unperm q . m n_head . m head_dim )
        ( __ft_unperm k2 . m n_kv . m head_dim )
    } {}
    ( __ft_slot_set . m wq L q )
    ( __ft_slot_set . m wk L k2 )
    ( __ft_slot_set . m wv L ( __ft_lw gg L `attn_v.weight` ok ) )
    ( __ft_slot_set . m wo L ( __ft_lw gg L `attn_output.weight` ok ) )
    ( __ft_slot_set . m wg L ( __ft_lw gg L `ffn_gate.weight` ok ) )
    ( __ft_slot_set . m wu L ( __ft_lw gg L `ffn_up.weight` ok ) )
    ( __ft_slot_set . m wd L ( __ft_lw gg L `ffn_down.weight` ok ) )
    ( __ft_vslot_set . m an L ( __ft_lvec gg L `attn_norm.weight` ) )
    ( __ft_vslot_set . m fn L ( __ft_lvec gg L `ffn_norm.weight` ) )
    ( __ft_vslot_set . m qn L ( __ft_lvec gg L `attn_q_norm.weight` ) )
    ( __ft_vslot_set . m kn L ( __ft_lvec gg L `attn_k_norm.weight` ) )
    ^ ok
}

unsafe @ __ft_layer_out * FtModelImpl m i L → v {
    ( __ft_slot_set . m wq L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wk L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wv L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wo L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wg L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wu L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wd L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_vslot_set . m an L ( __ft_nov ) )
    ( __ft_vslot_set . m fn L ( __ft_nov ) )
    ( __ft_vslot_set . m qn L ( __ft_nov ) )
    ( __ft_vslot_set . m kn L ( __ft_nov ) )
}

// Fill every lazy base const's device buffer. Call once, right after the
// capture; T when every tensor landed.
unsafe @ ft_stream_upload FtModel m__h GProg pg → b {
    : *FtModelImpl m ( __FtModel_ptr m__h )
    ? . m stream {} { ^ T }
    : i n ( vec_len [i] . m lz_node )
    ? > n 0 {} { ^ F }
    : ~ b ok T
    ?? ( gguf_open ( string_data . m src_path ) ) {
        T gg → {
            : ~ i k 0
            ~ & < k n ok {
                : i node ( _ti . m lz_node k )
                : i key ( _ti . m lz_key k )
                : i L / key 16
                : i slot % key 16
                ? == slot 15 { = ok ( __ft_up_wout m gg pg node ) }
                { = ok ( __ft_up_layer m gg pg node L slot ) }
                = k + k 1
            }
        }
        F e → { = ok F }
    }
    ^ ok
}

// ── the window schedule ──────────────────────────────────────────────
//
// Window for step st: (st · stride) mod nwin. Stride 1 is the sequential
// legacy order — which means a run shorter than one epoch reads ONLY the
// first steps·seq tokens of the corpus (a 4000-step seq-56 run over a
// 7.4M-token corpus sees 3% of it, all from the front). A stride COPRIME
// with nwin makes the schedule a permutation of the windows: any prefix
// of it samples the whole corpus evenly, and a full epoch still visits
// every window exactly once.

@ __ft_gcd i a i b2 → i {
    : ~ i x a
    : ~ i y b2
    ~ != y 0 {
        : i t2 % x y
        = x y
        = y t2
    }
    ^ x
}

// The golden-ratio point of [1, nwin), nudged up to the nearest value
// coprime with nwin — consecutive steps land maximally far apart.
@ ft_auto_stride i nwin → i {
    ? > nwin 2 {} { ^ 1 }
    : ~ i s2 # i * 0.6180339887498949 # f nwin
    ? < s2 1 { = s2 1 } {}
    ~ != ( __ft_gcd s2 nwin ) 1 { = s2 + s2 1 }
    = s2 % s2 nwin
    ? == s2 0 { = s2 1 } {}
    ^ s2
}

@ ft_win_at i st i nwin i stride → i {
    ? > nwin 0 {} { ^ 0 }
    ^ % * st stride nwin
}

// ── checkpointing: adapters + Adam state + step, resumable ───────────
//
// A crash five hours into a run must not cost the run. Every `ckevery`
// steps the trainer writes one safetensors file: the LoRA parameter
// values, both Adam moment vectors, the optimizer's step counter and the
// step index — everything the update rule reads. --resume loads it and
// continues; with f32 device storage (--mixed / --f32) the f32 file is a
// lossless round-trip, so a resumed run replays the uninterrupted one.
// The write goes to `<path>.tmp` then rename(2)s over, so a crash mid-
// write leaves the previous checkpoint intact.

@ __ft_ckpt_name s kind i pi → String {
    : String nm ( string_from `ckpt.` )
    ( string_push_str nm kind )
    ( string_push_str nm `.` )
    ( string_push_str nm ( nurl_str_int pi ) )
    ^ nm
}

// The element count of pids entry `pi` (A blocks are even, B odd).
@ __ft_ckpt_n * FtModelImpl m i r i pi → i {
    : i sl / pi 2
    ? == % pi 2 0 { ^ * ( __ft_ain m sl ) r } {}
    ^ * r ( __ft_aout m sl )
}

// One checkpoint tensor, stored at the DEVICE's precision: f64 replay
// (dtype 0) writes F64, f32/mixed write F32 — either way the file holds
// exactly what the device buffers hold, so a resume is a lossless
// round-trip for every capture dtype.
@ __ft_ckpt_add StWriter so s name ( Vec f ) val i n i dtype → v {
    ? == dtype 0 {
        : ( Vec i ) sh ( vec_new [i] )
        ( vec_push [i] sh n )
        ( stw_add_f64 so name sh val )
    } { ( __ft_st_add so name val n 0 ) }
}

@ __ft_ckpt_save s path * FtModelImpl m i r GProg pg GpOpt go ( Vec i ) pids i nslot i step i dtype i wstr → b {
    : StWriter so ( stw_new )
    : ( Vec i ) meta ( vec_new [i] )
    ( vec_push [i] meta 1 )
    ( vec_push [i] meta step )
    ( vec_push [i] meta ( gpopt_t go ) )
    ( vec_push [i] meta nslot )
    ( vec_push [i] meta r )
    ( vec_push [i] meta wstr )
    : ( Vec i ) msh ( vec_new [i] )
    ( vec_push [i] msh 6 )
    ( stw_add_i64 so `ckpt.meta` msh meta )
    : ~ b ok T
    : ~ i pi 0
    ~ & < pi * 2 nslot ok {
        : i n ( __ft_ckpt_n m r pi )
        : ( Vec f ) val ( vec_with_cap [f] n )
        : ~ i k 0
        ~ < k n { ( vec_push [f] val 0.0 ) = k + k 1 }
        = ok & ok ( gput_value pg @ GVar { ( _ti pids pi ) } val )
        ? ok {
            : String nm ( __ft_ckpt_name `p` pi )
            ( __ft_ckpt_add so ( string_data nm ) val n dtype )
        } {}
        = ok & ok ( gpopt_m_download go pg pi val )
        ? ok {
            : String nm ( __ft_ckpt_name `m` pi )
            ( __ft_ckpt_add so ( string_data nm ) val n dtype )
        } {}
        = ok & ok ( gpopt_v_download go pg pi val )
        ? ok {
            : String nm ( __ft_ckpt_name `v` pi )
            ( __ft_ckpt_add so ( string_data nm ) val n dtype )
        } {}
        = pi + pi 1
    }
    ? ok {
        : String tmp ( string_from path )
        ( string_push_str tmp `.tmp` )
        ?? ( stw_write so ( string_data tmp ) ) {
            T _ → {
                ?? ( fs_rename ( string_data tmp ) path ) {
                    T _ → {}
                    F _ → { = ok F }
                }
            }
            F e → { = ok F }
        }
    } {}
    ^ ok
}

// f32 little-endian bytes (st_dequant's output) → f64 values.
@ __ft_ckpt_vals ( Vec u ) by → ( Vec f ) {
    : i n / ( vec_len [u] by ) 4
    : ( Vec f ) o ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        : i p * k 4
        : i b0 # i ?? ( vec_get [u] by p ) { T x → x F → # u 0 }
        : i b1 # i ?? ( vec_get [u] by + p 1 ) { T x → x F → # u 0 }
        : i b2 # i ?? ( vec_get [u] by + p 2 ) { T x → x F → # u 0 }
        : i b3 # i ?? ( vec_get [u] by + p 3 ) { T x → x F → # u 0 }
        : i bits + + + b0 * b1 256 * b2 65536 * b3 16777216
        ( vec_push [f] o # f ( bits_to_f32 bits ) )
        = k + k 1
    }
    ^ o
}

// An F64 checkpoint tensor read raw off the mapping — st_dequant narrows
// everything through f32, which would round an f64-replay checkpoint.
unsafe @ __ft_ckpt_vals64 St st StTensor t → ( Vec f ) {
    : *u P ( st_tensor_ptr st t )
    : i n . t nelems
    : ( Vec f ) o ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] o ( bits_to_f64 ( nurl_peek P k ) ) )
        = k + k 1
    }
    ^ o
}

// One checkpoint tensor into a Vec f of exactly `want` elements, at the
// precision the file stored (F64 raw, everything else via st_dequant).
@ __ft_ckpt_read St st s kind i pi i want → !( Vec f ) String {
    : String nm ( __ft_ckpt_name kind pi )
    : i ti ( st_find_tensor st ( string_data nm ) )
    ? >= ti 0 {} {
        ^ @ !( Vec f ) String { F ( string_from `finetune: checkpoint tensor missing` ) }
    }
    // fallback dtype -1: never ST_F64 (0), so a failed get cannot fall
    // into the raw-pointer path
    : StTensor tt ?? ( vec_get [StTensor] ( st_tensors st ) ti ) {
        T x → x
        F → @ StTensor { ( string_new ) -1 0 0 0 0 0 0 0 0 }
    }
    ? == . tt dtype ST_F64 {
        : ( Vec f ) o ( __ft_ckpt_vals64 st tt )
        ? == ( vec_len [f] o ) want { ^ @ !( Vec f ) String { T o } } {}
        ^ @ !( Vec f ) String { F ( string_from `finetune: checkpoint tensor size mismatch` ) }
    } {}
    ?? ( st_dequant st ti ) {
        T by → {
            : ( Vec f ) o ( __ft_ckpt_vals by )
            ? == ( vec_len [f] o ) want { ^ @ !( Vec f ) String { T o } } {}
            ^ @ !( Vec f ) String { F ( string_from `finetune: checkpoint tensor size mismatch` ) }
        }
        F e → { ^ @ !( Vec f ) String { F e } }
    }
}

// Load `path` into the captured program + optimizer. T on success, with
// stepb holding the completed-step count. F = no usable checkpoint (the
// caller starts fresh); a shape/meta MISMATCH also reports F after
// printing why — resuming a different run over it would be silent ruin,
// so the caller must treat mismatch as fatal (mismb is poked 1).
@ __ft_ckpt_load s path * FtModelImpl m i r GProg pg GpOpt go ( Vec i ) pids i nslot i wstr inout i stepout inout b mismatch → b {
    = mismatch F
    ?? ( st_open path ) {
        T st → {
            : ~ b ok T
            : ~ i step 0
            : ~ i t 0
            : i mi ( st_find_tensor st `ckpt.meta` )
            ? >= mi 0 {} { = ok F }
            ? ok {
                ?? ( st_dequant st mi ) {
                    T by → {
                        : ( Vec f ) mv ( __ft_ckpt_vals by )
                        // 5 entries = a pre-stride checkpoint (its schedule
                        // was the sequential stride 1)
                        : i mn ( vec_len [f] mv )
                        ? | == mn 5 == mn 6 {
                            : i ver # i ( _tf mv 0 )
                            = step # i ( _tf mv 1 )
                            = t # i ( _tf mv 2 )
                            : i cslot # i ( _tf mv 3 )
                            : i cr # i ( _tf mv 4 )
                            : i cws ? == mn 6 # i ( _tf mv 5 ) 1
                            ? & & == ver 1 == cslot nslot == cr r {} {
                                ( nurl_eprintln `nurllama: checkpoint does not match this run (model/rank differ)` )
                                = mismatch T
                                = ok F
                            }
                            ? == cws wstr {} {
                                ( nurl_eprintln `nurllama: checkpoint was trained with a different --window-stride — resuming would silently change which data the run sees` )
                                = mismatch T
                                = ok F
                            }
                        } { = ok F }
                    }
                    F e → { = ok F }
                }
            } {}
            : ~ i pi 0
            ~ & < pi * 2 nslot ok {
                : i n ( __ft_ckpt_n m r pi )
                ?? ( __ft_ckpt_read st `p` pi n ) {
                    T val → {
                        = ok ( gput_set_input pg @ GVar { ( _ti pids pi ) } val )
                    }
                    F e → { = ok F }
                }
                ? ok {
                    ?? ( __ft_ckpt_read st `m` pi n ) {
                        T val → {
                            = ok ( gpopt_m_upload go pg pi val )
                        }
                        F e → { = ok F }
                    }
                } {}
                ? ok {
                    ?? ( __ft_ckpt_read st `v` pi n ) {
                        T val → {
                            = ok ( gpopt_v_upload go pg pi val )
                        }
                        F e → { = ok F }
                    }
                } {}
                = pi + pi 1
            }
            ? ok {
                = stepout step
                ( gpopt_set_t go t )
            } {}
            ^ ok
        }
        F e → { ^ F }
    }
}

@ ft_train FtModel m__h ( Vec i ) corpus i win i r f alpha i seed i steps f lr i dtype b verbose → FtTrain {
    ^ ( ft_train_ck m__h corpus win r alpha seed steps lr dtype verbose `` 0 F 1 )
}

// wstride: 1 = sequential legacy order · 0 = auto (golden-ratio coprime,
// ft_auto_stride) · else used as given, mod nwin.
unsafe @ ft_train_ck FtModel m__h ( Vec i ) corpus i win i r f alpha i seed i steps f lr i dtype b verbose s ckptp i ckevery b resume i wstride → FtTrain {
    : *FtModelImpl m ( __FtModel_ptr m__h )
    : i total ( vec_len [i] corpus )
    : ~ i T2 win
    ? > T2 total { = T2 total } {}
    : ~ i nwin / total T2
    ? < nwin 1 { = nwin 1 } {}
    : ~ i wstr wstride
    ? == wstr 0 { = wstr ( ft_auto_stride nwin ) } {}
    ? < wstr 1 { = wstr 1 } {}
    ? >= wstr nwin { = wstr % wstr nwin ? == wstr 0 { = wstr 1 } {} } {}
    ? verbose {
        ( nurl_print `windows: ` )
        ( nurl_print ( nurl_str_int nwin ) )
        ( nurl_print ` · stride ` )
        ( nurl_print ( nurl_str_int wstr ) )
        ( nurl_print ? == wstr 1 ` (sequential)\n` ` (spread)\n` )
    } {}
    : ( Vec i ) ids ( vec_with_cap [i] T2 )
    : ~ i k0 0
    ~ < k0 T2 { ( vec_push [i] ids ( _ti corpus k0 ) ) = k0 + k0 1 }
    : i nslot * 7 . m n_layer
    : ( Vec i ) pids ( vec_new [i] )
    // ft_graph needs the base matrices; a prior ft_train may have dropped
    // them (they only live host-side to build the graph), and a prior
    // ft_merge_st consumed the embedding table. Stream them back.
    ? | == ( vec_len [FtW] . m wq ) 0 == ( vec_len [f] . m embd ) 0 { : b _r ( ft_reload_base m__h ) } {}
    : GTape tp ( tape_new )
    : FtG fg ( ft_graph m__h tp ids r alpha seed pids )
    : ( Vec f ) aflat ( vec_new [f] )
    : ( Vec f ) bflat ( vec_new [f] )
    ? ( tape_ok tp ) {} {
        ^ @ FtTrain { F 0.0 0.0 aflat bflat }
    }
    : GpuKit kit ( gk_open 0 )
    : ~ b ok ( gk_ok kit )
    : ~ f l0 0.0
    : ~ f l1 0.0
    ? ok {
        : GProg pg ( gput_capture_dt kit tp . fg loss dtype )
        = ok ( gput_ok pg )
        // streamed base: the capture allocated the buffers from the shapes,
        // now fill them one tensor at a time
        ? ok { = ok ( ft_stream_upload m__h pg ) } {}
        // The base weights are now on the device; their f64 host copies are
        // dead weight during training. Free BOTH the tape's const nodes and
        // the model's per-layer base matrices — host RAM drops to the
        // adapters + activations. The base streams back from the GGUF for the
        // merge (ft_reload_base). Training reads device buffers only.
        ? ok { ( tape_drop_consts tp ) ( ft_drop_base m__h ) } {}
        : GpOpt go ( gpopt_adam_new lr )
        : ~ i pi 0
        ~ < pi * 2 nslot {
            ( gpopt_add go pg @ GVar { ( _ti pids pi ) } 0.0 )
            = pi + pi 1
        }
        : ~ i st 0
        ? & & ok resume > ( nurl_str_len ckptp ) 0 {
            : ~ i stl 0
            : ~ b mism F
            ? ( __ft_ckpt_load ckptp m r pg go pids nslot wstr stl mism ) {
                = st stl
                ( nurl_print `resumed from checkpoint: step ` )
                ( nurl_print ( nurl_str_int st ) )
                ( nurl_print `/` )
                ( nurl_print ( nurl_str_int steps ) )
                ( nurl_print `\n` )
            } {
                ? mism { = ok F } {
                    ( nurl_print `no usable checkpoint — starting from step 0\n` )
                }
            }
        } {}
        : ~ i cur 0
        : ~ b first T
        ~ & < st steps ok {
            // window switch: refresh the two input consts
            : i w ( ft_win_at st nwin wstr )
            ? & > nwin 1 != w cur {
                : ( Vec i ) wids ( vec_with_cap [i] T2 )
                : ~ i q 0
                ~ < q T2 { ( vec_push [i] wids ( _ti corpus + * w T2 q ) ) = q + q 1 }
                : ( Vec f ) xr ( ft_embed m__h wids )
                = ok & ok ( gput_set_input pg . fg xin xr )
                : ( Vec f ) ohr ( ft_onehot m__h wids )
                = ok & ok ( gput_set_input pg . fg ohin ohr )
                = cur w
            } {}
            = ok & ok ( gput_forward pg )
            = ok & ok ( gput_backward pg )
            : f lc ( gput_loss pg )
            ? first { = l0 lc = first F } {}
            ? == st - steps 1 { = l1 lc } {}
            ? & verbose == % st 10 0 {
                ( nurl_print `step ` ) ( nurl_print ( nurl_str_int st ) )
                ( nurl_print ` loss ` ) ( nurl_print ( nurl_str_float lc ) )
                ( nurl_print `\n` )
            } {}
            = ok & ok ( gpopt_step go pg )
            = st + st 1
            ? & & & ok > ( nurl_str_len ckptp ) 0 > ckevery 0 == % st ckevery 0 {
                ? ( __ft_ckpt_save ckptp m r pg go pids nslot st dtype wstr ) {
                    ? verbose {
                        ( nurl_print `checkpoint: step ` )
                        ( nurl_print ( nurl_str_int st ) )
                        ( nurl_print ` → ` )
                        ( nurl_print ckptp )
                        ( nurl_print `\n` )
                    } {}
                } { ( nurl_eprintln `nurllama: checkpoint save failed (training continues)` ) }
            } {}
        }
        // final state, so a crash in the adapter save / merge that follows
        // resumes here instead of retraining
        ? & ok > ( nurl_str_len ckptp ) 0 {
            ? ( __ft_ckpt_save ckptp m r pg go pids nslot st dtype wstr ) {} {
                ( nurl_eprintln `nurllama: final checkpoint save failed` )
            }
        } {}
        = ok & ok ( gput_param_sync_host pg tp )
    } {}
    // download the trained values from the tape
    : ~ i sl 0
    ~ < sl nslot {
        : GVar pa @ GVar { ( _ti pids * sl 2 ) }
        : GVar pb @ GVar { ( _ti pids + * sl 2 1 ) }
        : Tensor ta ( gvar_value tp pa )
        : Tensor tb ( gvar_value tp pb )
        : ~ i k 0
        ~ < k ( vec_len [f] . ta data ) { ( vec_push [f] aflat ( _tf . ta data k ) ) = k + k 1 }
        = k 0
        ~ < k ( vec_len [f] . tb data ) { ( vec_push [f] bflat ( _tf . tb data k ) ) = k + k 1 }
        = sl + sl 1
    }
    ^ @ FtTrain { ok l0 l1 aflat bflat }
}

// ── safetensors output (via the safetensor package's writer) ─────────

// Add one F32 tensor with shape [d0] (d1==0) or [d0,d1].
@ __ft_st_add StWriter w s name ( Vec f ) v i d0 i d1 → v {
    : ( Vec i ) sh ( vec_new [i] )
    ( vec_push [i] sh d0 )
    ? > d1 0 { ( vec_push [i] sh d1 ) } {}
    ( stw_add_f32 w name sh v )
}

// Save trained adapters as a safetensors file: per slot,
// blk.<L>.<which>.lora_a [in,r] and .lora_b [r,out], F32.
unsafe @ ft_adapters_save s path FtModel m__h FtTrain t i r → !v String {
    : *FtModelImpl m ( __FtModel_ptr m__h )
    : StWriter so ( stw_new )
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
        ( __ft_st_add so ( string_data na ) av in r )
        : ( Vec f ) bv ( vec_with_cap [f] * r out )
        = k 0
        ~ < k * r out { ( vec_push [f] bv ( _tf . t bflat + boff k ) ) = k + k 1 }
        ( __ft_st_add so ( string_data nb ) bv r out )
        = aoff + aoff * in r
        = boff + boff * r out
        ? & . m stream == w 6 { ( __ft_layer_out m L ) } {}
        = sl + sl 1
    }
    ? . m stream {
        // the merge's GGUF leaves the model (closed here)
        : Gguf mgg . m mgg
        ( mem_take mgg )
        = . m mgg ( gguf_none )
    } {}
    : !v String res ( stw_write so path )
    ^ res
}

// The slot's adapter tensor name, matching ft_adapters_save exactly.
@ __ft_adapter_name i sl s suffix → String {
    : i L / sl 7
    : i w % sl 7
    : ~ s wn `q`
    ? == w 1 { = wn `k` } {}
    ? == w 2 { = wn `v` } {}
    ? == w 3 { = wn `o` } {}
    ? == w 4 { = wn `gate` } {}
    ? == w 5 { = wn `up` } {}
    ? == w 6 { = wn `down` } {}
    : String nm ( string_from `blk.` )
    ( string_push_str nm ( nurl_str_int L ) )
    ( string_push_str nm `.` )
    ( string_push_str nm wn )
    ( string_push_str nm suffix )
    ^ nm
}

// Read a saved adapters file back into an FtTrain (per-slot A blocks then
// B blocks, flat, exactly as ft_train downloads them) — the merge path's
// input when the training happened in ANOTHER process: `finetune
// --merge-only` after a crash between the adapter save and the merge, or
// merging an adapter file someone shipped. The rank is read from the
// file's own blk.0.q.lora_a [in, r] shape and stored into `rank`.
unsafe @ ft_adapters_load s path FtModel m__h inout i rank → !FtTrain String {
    : *FtModelImpl m ( __FtModel_ptr m__h )
    ?? ( st_open path ) {
        T st → {
            : ~ i r 0
            : i ti0 ( st_find_tensor st `blk.0.q.lora_a` )
            ? >= ti0 0 {
                ?? ( vec_get [StTensor] ( st_tensors st ) ti0 ) { T t → { = r . t d1 } F → {} }
            } {}
            ? & > r 0 <= r 4096 {} {
                ^ @ !FtTrain String { F ( string_from `finetune: not an adapters file (blk.0.q.lora_a missing or malformed)` ) }
            }
            : i nslot * 7 . m n_layer
            : ( Vec f ) aflat ( vec_new [f] )
            : ( Vec f ) bflat ( vec_new [f] )
            : ~ b ok T
            : ~ i sl 0
            ~ & < sl nslot ok {
                : i in ( __ft_ain m sl )
                : i out ( __ft_aout m sl )
                : String na ( __ft_adapter_name sl `.lora_a` )
                : i ta ( st_find_tensor st ( string_data na ) )
                : String nb ( __ft_adapter_name sl `.lora_b` )
                : i tb ( st_find_tensor st ( string_data nb ) )
                ? & >= ta 0 >= tb 0 {} { = ok F }
                ? ok {
                    ?? ( st_dequant st ta ) {
                        T by → {
                            : ( Vec f ) av ( __ft_ckpt_vals by )
                            ? == ( vec_len [f] av ) * in r {
                                : ~ i k 0
                                ~ < k * in r { ( vec_push [f] aflat ( _tf av k ) ) = k + k 1 }
                            } { = ok F }
                        }
                        F e → { = ok F }
                    }
                } {}
                ? ok {
                    ?? ( st_dequant st tb ) {
                        T by → {
                            : ( Vec f ) bv ( __ft_ckpt_vals by )
                            ? == ( vec_len [f] bv ) * r out {
                                : ~ i k 0
                                ~ < k * r out { ( vec_push [f] bflat ( _tf bv k ) ) = k + k 1 }
                            } { = ok F }
                        }
                        F e → { = ok F }
                    }
                } {}
                = sl + sl 1
            }
            ? ok {} {
                ^ @ !FtTrain String { F ( string_from `finetune: adapters file does not match this model (missing slot or shape mismatch)` ) }
            }
            = rank r
            ^ @ !FtTrain String { T @ FtTrain { T 0.0 0.0 aflat bflat } }
        }
        F e → { ^ @ !FtTrain String { F e } }
    }
}

// ── merge: base + (α/r)·A·B → a full-weights safetensors file ────────
// nurllama's verified `--weights` path (llm_open_st) then runs the merged
// model with the GGUF supplying metadata + tokenizer. Weights are emitted
// [out, in] F32 under HF names in TRUE HF lane order — llm_open_st
// interleaves NORM-rope q/k at load, exactly like llama.cpp's converter
// does for GGUFs, so the file is a genuine HF checkpoint.

// merged tape-layout [in,out] → emit [out,in] rows; q/k: NORM re-permute.
@ __ft_emit_w StWriter so s name FtW w b reperm i heads i hd → v {
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
    ( __ft_st_add so name e out in )
}

// Merge every adapter into its base weight and write the FULL model as a
// safetensors file — run it with nurllama's --weights path (llm_open_st).
@ ft_merge_st s path FtModel m__h FtTrain t i r f alpha → !v String {
    ^ ( ft_merge_st_mask path m__h t r alpha 15 )
}

// mask bit0 = embeddings, bit1 = attention projections, bit2 = mlp
// projections (a bisect handle for the merged-path diagnostics).
unsafe @ ft_merge_st_mask s path FtModel m__h FtTrain t i r f alpha i mask → !v String {
    : *FtModelImpl m ( __FtModel_ptr m__h )
    : f scale / alpha # f r
    // The per-layer base matrices were freed after device capture
    // (ft_drop_base); stream them back for the merge (identical loader path,
    // so the NORM-rope un-permute matches byte-for-byte). No-op if resident.
    ? == ( vec_len [FtW] . m wq ) 0 {
        ? ( ft_reload_base m__h ) {} {
            ^ @ !v String { F ( string_from `finetune: cannot reload base weights for merge` ) }
        }
    } {}
    // A streamed model holds shape-only placeholders, so the check above
    // cannot see that the values are missing — merging them would write a
    // model of zeros. Hold the GGUF open and page one layer in at a time.
    ? . m stream {
        ?? ( gguf_open ( string_data . m src_path ) ) {
            T gg → { = . m mgg gg }
            F e → { ^ @ !v String { F e } }
        }
    } {}
    : StWriter so ( stw_new )
    // embeddings + final norm (frozen; [V,H] is already [out,in]).
    // The merge CONSUMES m.embd: once its bytes are in the writer the 3 GB
    // f64 host copy has no further reader here, and every caller merges
    // once and then lets the model go — keeping it alive would stack it on
    // top of the writer's own copy for the rest of the merge. So the
    // embedding leaves the model here and is dropped at the end of this
    // arm, before the first layer is merged.
    ? == % mask 2 1 {
        : ( Vec f ) embd . m embd
        ( mem_take embd )
        = . m embd ( vec_new [f] )
        ( __ft_st_add so `model.embed_tokens.weight` embd . m n_vocab . m n_embd )
    } {}
    ? == % / mask 8 2 1 {
        ( __ft_st_add so `model.norm.weight` . m norm_f . m n_embd 0 )
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
        // streamed model: this layer's base is not resident — bring it in
        // for its seven slots and drop it again after the last one, so the
        // merge costs one layer of host RAM, not the whole model
        ? & . m stream == w 0 {
            : b _li ( __ft_layer_in . m mgg m L )
        } {}
        // the per-layer norms, once per layer (at slot 0; norm mask bit3)
        ? & == w 0 == % / mask 8 2 1 {
            : FtV anv ?? ( vec_get [FtV] . m an L ) { T x → x F → ( __ft_nov ) }
            : String n1 ( string_from `model.layers.` )
            ( string_push_str n1 ( nurl_str_int L ) )
            ( string_push_str n1 `.input_layernorm.weight` )
            ( __ft_st_add so ( string_data n1 ) . anv v . m n_embd 0 )
            : FtV fnv ?? ( vec_get [FtV] . m fn L ) { T x → x F → ( __ft_nov ) }
            : String n2 ( string_from `model.layers.` )
            ( string_push_str n2 ( nurl_str_int L ) )
            ( string_push_str n2 `.post_attention_layernorm.weight` )
            ( __ft_st_add so ( string_data n2 ) . fnv v . m n_embd 0 )
            // qwen3's per-head Q/K norms are frozen too, but a merged
            // model without them is a DIFFERENT model — emit when present.
            : FtV qnv ?? ( vec_get [FtV] . m qn L ) { T x → x F → ( __ft_nov ) }
            ? . qnv has {
                : String n3 ( string_from `model.layers.` )
                ( string_push_str n3 ( nurl_str_int L ) )
                ( string_push_str n3 `.self_attn.q_norm.weight` )
                ( __ft_st_add so ( string_data n3 ) . qnv v . m head_dim 0 )
            } {}
            : FtV knv ?? ( vec_get [FtV] . m kn L ) { T x → x F → ( __ft_nov ) }
            ? . knv has {
                : String n4 ( string_from `model.layers.` )
                ( string_push_str n4 ( nurl_str_int L ) )
                ( string_push_str n4 `.self_attn.k_norm.weight` )
                ( __ft_st_add so ( string_data n4 ) . knv v . m head_dim 0 )
            } {}
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
        // TRUE HF layout: the tape's un-permuted half-split q/k IS the HF
        // lane order, and llm_open_st now interleaves NORM-rope q/k at load
        // (the same permutation llama.cpp's converter bakes into GGUFs) —
        // so the file stays a genuine HF checkpoint, runnable anywhere.
        : b reperm F
        : i heads ? == w 0 . m n_head . m n_kv
        : b want ? <= w 3 == % / mask 2 2 1 == % / mask 4 2 1
        ? want { ( __ft_emit_w so ( string_data nm ) mw reperm heads . m head_dim ) } {}
        // (`md` lives in `mw` now, which drops it.)
        // qwen2 q/k/v biases pass through unmerged (NEOX: no reperm)
        ? <= w 2 {
            : ~ FtV bv2 ( __ft_nov )
            ? == w 0 { = bv2 ?? ( vec_get [FtV] . m bq L ) { T x → x F → bv2 } } {}
            ? == w 1 { = bv2 ?? ( vec_get [FtV] . m bk L ) { T x → x F → bv2 } } {}
            ? == w 2 { = bv2 ?? ( vec_get [FtV] . m bv L ) { T x → x F → bv2 } } {}
            ? . bv2 has {
                : ~ s bn `self_attn.q_proj.bias`
                ? == w 1 { = bn `self_attn.k_proj.bias` } {}
                ? == w 2 { = bn `self_attn.v_proj.bias` } {}
                : String nb ( string_from `model.layers.` )
                ( string_push_str nb ( nurl_str_int L ) )
                ( string_push_str nb `.` )
                ( string_push_str nb bn )
                ( __ft_st_add so ( string_data nb ) . bv2 v out 0 )
            } {}
        } {}
        = aoff + aoff * in r
        = boff + boff * r out
        // page the layer's f64 base back OUT after its last slot — without
        // this a streamed merge held every visited layer resident (~850 MB
        // each on a 4B model, ~30 GB by the last layer: the OOM the layer
        // paging exists to prevent). ft_adapters_save already did this.
        ? & . m stream == w 6 { ( __ft_layer_out m L ) } {}
        = sl + sl 1
    }
    : !v String res ( stw_write so path )
    ^ res
}

// ── the CLI driver ───────────────────────────────────────────────────
// nurllama finetune <model.gguf> <data.txt>: tokenize the corpus with the
// model's own tokenizer, LoRA-train on the DEVICE over the first `seq`
// tokens (v1 trains one fixed window — the captured graph has a fixed
// shape; multi-window scheduling lands with gput_set_input plumbing),
// save the adapters, and optionally write a merged full-model safetensors
// runnable via `nurllama run model.gguf PROMPT --weights merged.st`.
@ nurllama_finetune s modp s datap s outp s mergedp i steps f lr i rank f alpha i seq i seed b f32 b mixed s ckptp i ckevery b resume i wstride b mergeonly → i {
    // --merge-only: no corpus, no tape, no device — read the adapters file
    // (--out) back and write the merged model. This is both a shipped-
    // adapter merger and the low-memory recovery path: the in-training
    // merge holds the capture's host structures UNDER the 16 GB the
    // full-model writer needs, which on a 31 GB box is the difference
    // between finishing and the OOM killer.
    ? mergeonly {
        ? > ( nurl_str_len mergedp ) 0 {} {
            ( nurl_eprintln `nurllama: --merge-only needs --merged <out.st>` )
            ^ 1
        }
        ?? ( ft_open modp ) {
            T m → {
                : ~ i rc 0
                : ~ i r 0
                ?? ( ft_adapters_load outp m r ) {
                    T tr → {
                        ( nurl_print `merge-only: adapters ` )
                        ( nurl_print outp )
                        ( nurl_print ` (rank ` )
                        ( nurl_print ( nurl_str_int r ) )
                        ( nurl_print `) + base → ` )
                        ( nurl_print mergedp )
                        ( nurl_print `\n` )
                        ?? ( ft_merge_st mergedp m tr r alpha ) {
                            T _ → {
                                ( nurl_print `merged model → ` )
                                ( nurl_print mergedp )
                                ( nurl_print `\n` )
                            }
                            F e → {
                                ( nurl_eprintln ( string_data e ) )
                                = rc 1
                            }
                        }
                    }
                    F e → {
                        ( nurl_eprintln ( string_data e ) )
                        = rc 1
                    }
                }
                ^ rc
            }
            F e → {
                ( nurl_eprintln ( string_data e ) )
                ^ 1
            }
        }
    } {}
    : ~ s text ``
    : ~ b haderr F
    : ~ String textS ( string_new )
    ?? ( read_file datap ) {
        T t → { = textS t = text ( string_data textS ) }
        F _ → {
            ( nurl_eprintln `nurllama: cannot read the data file` )
            = haderr T
        }
    }
    ? haderr { ^ 1 } {}
    : ( Vec i ) ids ( vec_new [i] )
    ?? ( gguf_open modp ) {
        T gg → {
            ?? ( tok_new gg ) {
                T tk → {
                    : ( Vec i ) enc ( tok_encode tk text T )
                    : ~ i k 0
                    ~ < k ( vec_len [i] enc ) { ( vec_push [i] ids ( _ti enc k ) ) = k + k 1 }
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                    = haderr T
                }
            }
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            = haderr T
        }
    }
    ? | haderr < ( vec_len [i] ids ) 4 {
        ( nurl_eprintln `nurllama: need at least 4 tokens of training data` )
        ^ 1
    } {}
    ( nurl_print `finetune: ` )
    ( nurl_print ( nurl_str_int ( vec_len [i] ids ) ) )
    ( nurl_print ` tokens · window ` )
    ( nurl_print ( nurl_str_int seq ) )
    ( nurl_print ` · rank ` )
    ( nurl_print ( nurl_str_int rank ) )
    ( nurl_print ` · alpha ` )
    ( nurl_print ( nurl_str_float alpha ) )
    ( nurl_print ` · ` )
    ( nurl_print ( nurl_str_int steps ) )
    ( nurl_print ` steps\n` )
    ?? ( ft_open modp ) {
        T m → {
            ( nurl_print `model: ` )
            ( nurl_print ( nurl_str_int ( ft_n_layer m ) ) )
            ( nurl_print ` layers · hidden ` )
            ( nurl_print ( nurl_str_int ( ft_n_embd m ) ) )
            ( nurl_print ` · building the tape + capturing onto the device\n` )
            : i dt ? mixed 2 ? f32 1 0
            ? mixed { ( nurl_print `precision: mixed (f32 storage, f64 accumulation — half VRAM, near-f64 accuracy)\n` ) } {}
            ? & f32 == mixed F { ( nurl_print `precision: float32 device replay (half VRAM; float32 precision, not bit-exact to f64)\n` ) } {}
            : FtTrain tr ( ft_train_ck m ids seq rank alpha seed steps lr dt T ckptp ckevery resume wstride )
            ? . tr ok {} {
                ( nurl_eprintln `nurllama: finetune training failed (no device? poisoned graph?)` )
                ^ 1
            }
            ( nurl_print `CE ` )
            ( nurl_print ( nurl_str_float . tr l0 ) )
            ( nurl_print ` → ` )
            ( nurl_print ( nurl_str_float . tr l1 ) )
            ( nurl_print `\n` )
            : ~ i rc 0
            ?? ( ft_adapters_save outp m tr rank ) {
                T _ → {
                    ( nurl_print `adapters → ` )
                    ( nurl_print outp )
                    ( nurl_print `\n` )
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                    = rc 1
                }
            }
            ? > ( nurl_str_len mergedp ) 0 {
                ?? ( ft_merge_st mergedp m tr rank alpha ) {
                    T _ → {
                        ( nurl_print `merged model → ` )
                        ( nurl_print mergedp )
                        ( nurl_print `  (run: nurllama run <model.gguf> PROMPT --weights ` )
                        ( nurl_print mergedp )
                        ( nurl_print `)\n` )
                    }
                    F e → {
                        ( nurl_eprintln ( string_data e ) )
                        = rc 1
                    }
                }
            } {}
            ^ rc
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ^ 1
        }
    }
}
