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
    // qwen3's per-head Q/K RMSNorm weights [head_dim], *( Vec f ) or 0.
    // Absent for llama/qwen2 — a 0 here simply skips the norm.
    ( Vec s ) qn ( Vec s ) kn
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
    i mgg  // a Gguf held open across a streamed merge (0 = none)
}

// Streaming base upload, OFF by default: the finetune tests compare the CPU
// tape's loss against the device's, and a lazy const has no host values to
// compare with. `nurllama finetune --stream` turns it on for models whose
// f64 host copy would not fit.
: ~ b __ft_stream_on F

@ ft_set_stream b on → v { = __ft_stream_on on }

@ __ft_stream_wanted → b { ^ __ft_stream_on }

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
    ( __ft_vfree . m qn ) ( __ft_vfree . m kn )
    ( vec_free [i] . m lz_node ) ( vec_free [i] . m lz_key )
    ( string_free . m src_path )
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

// The tape-layout SHAPE of a layer weight, read from the GGUF's tensor
// table without touching a byte of its data. Rows/cols mirror __ft_raw +
// __ft_transpose exactly: rows = d0 (in), cols = d1 (out). An absent tensor
// gives 0×0, which callers read as "not present".
@ __ft_lshape * Gguf gg i layer s suffix * u rowsb * u colsb → v {
    ( nurl_poke rowsb 0 0 )
    ( nurl_poke colsb 0 0 )
    : String nm ( __ft_lname layer suffix )
    : i idx ( gguf_find_tensor gg ( string_data nm ) )
    ( string_free nm )
    ? >= idx 0 {} { ^ v }
    ?? ( vec_get [GgufTensor] . gg tensors idx ) {
        T t → {
            ( nurl_poke rowsb 0 . t d0 )
            ( nurl_poke colsb 0 . t d1 )
        }
        F → {}
    }
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
// Load every per-layer base matrix (q/k/v/o + gate/up/down) and the biases
// / norms into `m`'s (already-created) vecs, un-permuting NORM-rope q/k the
// same way whether called at open or at merge-time reload. `gg` stays the
// caller's to close. Poisons m.ok on a missing tensor.
// One shape-only per-layer weight: real rows/cols, no data.
@ __ft_shape_push * Gguf gg i L s suffix ( Vec FtW ) dst * u rb * u cb → v {
    ( __ft_lshape gg L suffix rb cb )
    ( vec_push [FtW] dst @ FtW { ( nurl_peek rb 0 ) ( nurl_peek cb 0 ) ( vec_new [f] ) } )
}

// One shape-only per-layer 1-D tensor: an FtV holding an empty vec when the
// model HAS this tensor, 0 when it does not (llama has no attn_q_norm).
@ __ft_shape_vec * Gguf gg i L s suffix ( Vec s ) dst → v {
    : String nm ( __ft_lname L suffix )
    : i idx ( gguf_find_tensor gg ( string_data nm ) )
    ( string_free nm )
    ? >= idx 0 {
        : *FtV p # *FtV ( nurl_alloc Z FtV )
        = . p v ( vec_new [f] )
        ( vec_push [s] dst # s p )
    } { ( vec_push [s] dst # s 0 ) }
}

// The streaming counterpart of __ft_load_bases: read every per-layer
// SHAPE and no data at all. ft_graph turns each into a lazy const and
// ft_stream_upload fills them one at a time after the capture.
@ __ft_load_shapes * Gguf gg * FtModel m → v {
    : *u rb ( nurl_alloc 8 )
    : *u cb ( nurl_alloc 8 )
    = . m n_ff 0
    : ~ i L 0
    ~ < L . m n_layer {
        ( __ft_shape_push gg L `attn_q.weight` . m wq rb cb )
        ( __ft_shape_push gg L `attn_k.weight` . m wk rb cb )
        ( __ft_shape_push gg L `attn_v.weight` . m wv rb cb )
        ( __ft_shape_push gg L `attn_output.weight` . m wo rb cb )
        ( __ft_shape_push gg L `ffn_gate.weight` . m wg rb cb )
        ? == . m n_ff 0 {
            ?? ( vec_get [FtW] . m wg L ) { T w → { = . m n_ff . w cols } F → {} }
        } {}
        ( __ft_shape_push gg L `ffn_up.weight` . m wu rb cb )
        ( __ft_shape_push gg L `ffn_down.weight` . m wd rb cb )
        ( __ft_shape_vec gg L `attn_q.bias` . m bq )
        ( __ft_shape_vec gg L `attn_k.bias` . m bk )
        ( __ft_shape_vec gg L `attn_v.bias` . m bv )
        ( __ft_shape_vec gg L `attn_norm.weight` . m an )
        ( __ft_shape_vec gg L `ffn_norm.weight` . m fn )
        ( __ft_shape_vec gg L `attn_q_norm.weight` . m qn )
        ( __ft_shape_vec gg L `attn_k_norm.weight` . m kn )
        = L + L 1
    }
    ( nurl_free rb ) ( nurl_free cb )
    ? > . m n_ff 0 {} { = . m ok F }
}

@ __ft_load_bases * Gguf gg * FtModel m → v {
    ? . m stream { ( __ft_load_shapes gg m ) ^ v } {}
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
        // qwen3 only; 0 everywhere else. NOT un-permuted for NORM rope:
        // the weight is per-LANE inside a head, and the un-permute
        // reorders lanes, so a NORM-rope model carrying these would need
        // the same reorder — none does (qwen3 is NEOX).
        ( vec_push [s] . m qn ( __ft_lvec gg L `attn_q_norm.weight` ) )
        ( vec_push [s] . m kn ( __ft_lvec gg L `attn_k_norm.weight` ) )
        = L + L 1
    }
    ? == ( nurl_peek okb 0 ) 1 {} { = . m ok F }
    ( nurl_free okb )
}

// Free the *FtV entries of `v` and EMPTY the vec (keep the handle valid so
// it can be re-pushed or finally vec_free'd).
@ __ft_clear_svec ( Vec s ) v → v {
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
    ( vec_clear [s] v )
}

// Drop the per-layer base matrices + biases/norms (the bulk of host RAM),
// emptying their vecs. embd / wout / norm_f are KEPT (embd feeds the
// per-window input recompute; the rest are small). Idempotent — a second
// call over empty vecs is a no-op — and reversible via ft_reload_base.
@ ft_drop_base * FtModel m → v {
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
    ( vec_clear [FtW] . m wq ) ( vec_clear [FtW] . m wk ) ( vec_clear [FtW] . m wv )
    ( vec_clear [FtW] . m wo ) ( vec_clear [FtW] . m wg ) ( vec_clear [FtW] . m wu )
    ( vec_clear [FtW] . m wd )
    ( __ft_clear_svec . m bq ) ( __ft_clear_svec . m bk ) ( __ft_clear_svec . m bv )
    ( __ft_clear_svec . m an ) ( __ft_clear_svec . m fn )
    ( __ft_clear_svec . m qn ) ( __ft_clear_svec . m kn )
}

// Re-stream the per-layer base from the source GGUF into `m`'s (empty)
// vecs — the reverse of ft_drop_base, using the SAME loader path so the
// NORM-rope un-permute is identical byte-for-byte. T on success.
@ ft_reload_base * FtModel m → b {
    ?? ( gguf_open ( string_data . m src_path ) ) {
        T gg → {
            ( __ft_load_bases gg m )
            ( gguf_close gg )
            ^ . m ok
        }
        F e → { ( string_free e ) ^ F }
    }
    ^ F
}

@ ft_open s path → !*FtModel String {
    ?? ( gguf_open path ) {
        T gg → {
            : s arch ( gguf_kv_str_or gg `general.architecture` `` )
            : *FtModel m # *FtModel ( nurl_alloc Z FtModel )
            = . m ok T
            = . m stream ( __ft_stream_wanted )
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
            // head_dim is NOT n_embd/n_head in general — qwen3-4B states
            // 128 against a 2560/32 = 80 — so read key_length when the
            // model publishes it. Everything downstream already sizes
            // attention off n_head·head_dim rather than n_embd.
            ? > . m n_head 0 { = . m head_dim / . m n_embd . m n_head } {}
            : String kb8 ( string_from arch )
            ( string_push_str kb8 `.attention.key_length` )
            = . m head_dim ( gguf_kv_int_or gg ( string_data kb8 ) . m head_dim )
            ( string_free kb8 )
            : String kb7 ( string_from arch )
            ( string_push_str kb7 `.rope.dimension_count` )
            = . m rope_dim ( gguf_kv_int_or gg ( string_data kb7 ) . m head_dim )
            ( string_free kb7 )
            // qwen2 and qwen3 both rotate the two halves of the span (NEOX);
            // llama rotates adjacent lanes (NORM, un-permuted at load).
            : b is_q3 != 0 ( nurl_str_eq arch `qwen3` )
            = . m rope_style ? | == ( nurl_str_eq arch `qwen2` ) 1 is_q3 1 0
            ? & > . m n_embd 0 > . m n_layer 0 {} {
                ( gguf_close gg )
                ( nurl_free # s m )
                ^ @ !*FtModel String { F ( string_from `finetune: not a llama/qwen2/qwen3 GGUF` ) }
            }
            // embeddings [vocab, n_embd]
            : *u rb ( nurl_alloc 8 )
            : *u cb ( nurl_alloc 8 )
            = . m embd ( __ft_raw gg `token_embd.weight` rb cb )
            = . m n_vocab ( nurl_peek rb 0 )
            ? > ( vec_len [f] . m embd ) 0 {} { = . m ok F }
            // lm_head: output.weight, or the tied embedding table. Streaming
            // takes its SHAPE only — a 151936 x 2560 f64 transpose is 3.1 GB
            // of host RAM that a device buffer needs for one upload.
            : i oi ( gguf_find_tensor gg `output.weight` )
            ? . m stream {
                = . m wout @ FtW { . m n_embd . m n_vocab ( vec_new [f] ) }
            } {
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
            = . m qn ( vec_new [s] )
            = . m kn ( vec_new [s] )
            = . m mgg 0
            = . m lz_node ( vec_new [i] )
            = . m lz_key ( vec_new [i] )
            = . m src_path ( string_from path )
            ( __ft_load_bases gg m )
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
    // A shape with no values is a STREAMED base weight: the capture sizes
    // its device buffer from the shape and ft_stream_upload fills it after,
    // so the whole model never sits in host RAM at once.
    : i nel * ? > r 0 r 1 c
    ? & == ( vec_len [f] v ) 0 > nel 0 {
        : GVar g ( grad_const_lazy tp s TE_F64 )
        ( vec_free [i] s )
        ^ g
    } {}
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
@ __ft_rec * FtModel m GVar g i L i k → GVar {
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
@ __ft_head_norm * GTape tp GVar x GVar W b have i T2 i heads i hd GVar ones f eps → GVar {
    ? have {} { ^ x }
    : ( Vec i ) flat_s ( vec_new [i] )
    ( vec_push [i] flat_s * T2 heads )
    ( vec_push [i] flat_s hd )
    : GVar flat ( g_reshape tp x flat_s )
    ( vec_free [i] flat_s )
    : GVar normed ( nn_rmsnorm tp flat W ones hd eps )
    : ( Vec i ) back_s ( vec_new [i] )
    ( vec_push [i] back_s T2 )
    ( vec_push [i] back_s * heads hd )
    : GVar o ( g_reshape tp normed back_s )
    ( vec_free [i] back_s )
    ^ o
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

// LoRA linear over the pids-registered adapter for `slot` (the plumbing;
// the math is nn_lora_linear).
@ __ft_lora_lin * GTape tp GVar x GVar w0 * u pids i slot f scale → GVar {
    : GVar pa @ GVar { ( nurl_peek pids * slot 2 ) }
    : GVar pb @ GVar { ( nurl_peek pids + * slot 2 1 ) }
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
    ( rng_free rg )
    // shared consts
    : ( Vec f ) xrows ( ft_embed m ids )
    : ~ GVar x ( __ft_const tp xrows T2 H )
    : GVar xin @ GVar { . x id }
    ( vec_free [f] xrows )
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
        : GVar Wq ( __ft_rec m ( __ft_const tp . qw data . qw rows . qw cols ) L 2 )
        : GVar Wk ( __ft_rec m ( __ft_const tp . kw data . kw rows . kw cols ) L 3 )
        : GVar Wv ( __ft_rec m ( __ft_const tp . vw data . vw rows . vw cols ) L 4 )
        : GVar Wo ( __ft_rec m ( __ft_const tp . ow data . ow rows . ow cols ) L 5 )
        : GVar Wg ( __ft_rec m ( __ft_const tp . gw data . gw rows . gw cols ) L 6 )
        : GVar Wu ( __ft_rec m ( __ft_const tp . uw data . uw rows . uw cols ) L 7 )
        : GVar Wd ( __ft_rec m ( __ft_const tp . dw data . dw rows . dw cols ) L 8 )
        : s anp ?? ( vec_get [s] . m an L ) { T x → x F → # s 0 }
        : *FtV anv # *FtV anp
        : GVar N1 ( __ft_rec m ( __ft_const tp . anv v 0 H ) L 0 )
        : s fnp ?? ( vec_get [s] . m fn L ) { T x → x F → # s 0 }
        : *FtV fnv # *FtV fnp
        : GVar N2 ( __ft_rec m ( __ft_const tp . fnv v 0 H ) L 1 )
        // qwen3's per-head Q/K norms, declared here so every base const of
        // this layer is created in one place (the streamer pairs by key).
        : s qnp ?? ( vec_get [s] . m qn L ) { T x → x F → # s 0 }
        : s knp ?? ( vec_get [s] . m kn L ) { T x → x F → # s 0 }
        : b haveqn != # i qnp 0
        : b havekn != # i knp 0
        : *FtV qnv # *FtV ? haveqn { qnp } { # s 0 }
        : *FtV knv # *FtV ? havekn { knp } { # s 0 }
        : ~ GVar QN @ GVar { -1 }
        : ~ GVar KN @ GVar { -1 }
        ? haveqn { = QN ( __ft_rec m ( __ft_const tp . qnv v 0 hd ) L 9 ) } {}
        ? havekn { = KN ( __ft_rec m ( __ft_const tp . knv v 0 hd ) L 10 ) } {}
        // attention
        : GVar xn ( nn_rmsnorm tp x N1 onesH H . m eps )
        : ~ GVar q ( __ft_lora_lin tp xn Wq pids + s7 0 scale )
        : ~ GVar kk ( __ft_lora_lin tp xn Wk pids + s7 1 scale )
        : ~ GVar vv ( __ft_lora_lin tp xn Wv pids + s7 2 scale )
        : s bqp ?? ( vec_get [s] . m bq L ) { T x → x F → # s 0 }
        ? != # i bqp 0 {
            : *FtV bqv # *FtV bqp
            = q ( g_add tp q ( __ft_rec m ( __ft_const tp . bqv v 0 * NH hd ) L 11 ) )
        } {}
        : s bkp ?? ( vec_get [s] . m bk L ) { T x → x F → # s 0 }
        ? != # i bkp 0 {
            : *FtV bkv # *FtV bkp
            = kk ( g_add tp kk ( __ft_rec m ( __ft_const tp . bkv v 0 * NKV hd ) L 12 ) )
        } {}
        : s bvp ?? ( vec_get [s] . m bv L ) { T x → x F → # s 0 }
        ? != # i bvp 0 {
            : *FtV bvv # *FtV bvp
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
    ( vec_free [f] oh )
    // next-token CE over rows 0..T-2 (the last position has no target)
    : GVar loss ( nn_cross_entropy_rows tp logits Oh onesV - T2 1 )
    ^ @ FtG { loss logits xin ohin * 7 . m n_layer }
}

// The one-hot rows for a window's ids (row t = ids[t+1]; last row zero).
@ ft_onehot * FtModel m ( Vec i ) ids → ( Vec f ) {
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

@ __ft_up_vec * FtModel m * Gguf gg * GProg pg i node i L s suf → b {
    : s p ( __ft_lvec gg L suf )
    ? != # i p 0 {} { ^ F }
    : *FtV pv # *FtV p
    ? == . m rope_style 0 {
        ? ( nurl_str_eq suf `attn_q.bias` ) { ( __ft_unperm_vec pv . m n_head . m head_dim ) } {}
        ? ( nurl_str_eq suf `attn_k.bias` ) { ( __ft_unperm_vec pv . m n_kv . m head_dim ) } {}
    } {}
    : b r ( gput_set_input pg @ GVar { node } . pv v )
    ( vec_free [f] . pv v )
    ( nurl_free p )
    ^ r
}

@ __ft_up_layer * FtModel m * Gguf gg * GProg pg i node i L i slot → b {
    : s suf ( __ft_base_name slot )
    ? | | | | | | == slot 0 == slot 1 == slot 9 == slot 10 == slot 11 == slot 12 == slot 13 {
        ^ ( __ft_up_vec m gg pg node L suf )
    } {}
    : *u okb ( nurl_alloc 8 )
    ( nurl_poke okb 0 1 )
    : FtW w ( __ft_lw gg L suf okb )
    : i lok ( nurl_peek okb 0 )
    ( nurl_free okb )
    ? == lok 1 {} { ( __ft_wfree w ) ^ F }
    ? == . m rope_style 0 {
        ? == slot 2 { ( __ft_unperm w . m n_head . m head_dim ) } {}
        ? == slot 3 { ( __ft_unperm w . m n_kv . m head_dim ) } {}
    } {}
    : b r ( gput_set_input pg @ GVar { node } . w data )
    ( __ft_wfree w )
    ^ r
}

@ __ft_up_wout * FtModel m * Gguf gg * GProg pg i node → b {
    : i oi ( gguf_find_tensor gg `output.weight` )
    ? >= oi 0 {
        : *u rb ( nurl_alloc 8 )
        : *u cb ( nurl_alloc 8 )
        : ( Vec f ) raw ( __ft_raw gg `output.weight` rb cb )
        : FtW w ( __ft_transpose raw ( nurl_peek rb 0 ) ( nurl_peek cb 0 ) )
        ( vec_free [f] raw )
        ( nurl_free rb ) ( nurl_free cb )
        : b r ( gput_set_input pg @ GVar { node } . w data )
        ( __ft_wfree w )
        ^ r
    } {}
    : FtW w2 ( __ft_transpose . m embd . m n_vocab . m n_embd )
    : b r2 ( gput_set_input pg @ GVar { node } . w2 data )
    ( __ft_wfree w2 )
    ^ r2
}

// ── one layer in, one layer out (the streamed merge) ──────────────────
//
// The merge walks the model layer by layer, so it needs exactly one layer
// of base weights resident at a time — the same trade the training path
// makes. These swap a layer's shape-only placeholders for the real tensors
// and back.

@ __ft_slot_set ( Vec FtW ) v i L FtW w → v {
    ?? ( vec_get [FtW] v L ) { T old → { ( __ft_wfree old ) } F → {} }
    ( vec_set [FtW] v L w )
}

@ __ft_vslot_set ( Vec s ) v i L s p → v {
    ?? ( vec_get [s] v L ) {
        T old → {
            ? != # i old 0 {
                : *FtV ov # *FtV old
                ( vec_free [f] . ov v )
                ( nurl_free old )
            } {}
        }
        F → {}
    }
    ( vec_set [s] v L p )
}

@ __ft_layer_in * Gguf gg * FtModel m i L → b {
    : *u okb ( nurl_alloc 8 )
    ( nurl_poke okb 0 1 )
    : FtW q ( __ft_lw gg L `attn_q.weight` okb )
    : FtW k2 ( __ft_lw gg L `attn_k.weight` okb )
    ? == . m rope_style 0 {
        ( __ft_unperm q . m n_head . m head_dim )
        ( __ft_unperm k2 . m n_kv . m head_dim )
    } {}
    ( __ft_slot_set . m wq L q )
    ( __ft_slot_set . m wk L k2 )
    ( __ft_slot_set . m wv L ( __ft_lw gg L `attn_v.weight` okb ) )
    ( __ft_slot_set . m wo L ( __ft_lw gg L `attn_output.weight` okb ) )
    ( __ft_slot_set . m wg L ( __ft_lw gg L `ffn_gate.weight` okb ) )
    ( __ft_slot_set . m wu L ( __ft_lw gg L `ffn_up.weight` okb ) )
    ( __ft_slot_set . m wd L ( __ft_lw gg L `ffn_down.weight` okb ) )
    ( __ft_vslot_set . m an L ( __ft_lvec gg L `attn_norm.weight` ) )
    ( __ft_vslot_set . m fn L ( __ft_lvec gg L `ffn_norm.weight` ) )
    ( __ft_vslot_set . m qn L ( __ft_lvec gg L `attn_q_norm.weight` ) )
    ( __ft_vslot_set . m kn L ( __ft_lvec gg L `attn_k_norm.weight` ) )
    : i r ( nurl_peek okb 0 )
    ( nurl_free okb )
    ^ == r 1
}

@ __ft_layer_out * FtModel m i L → v {
    ( __ft_slot_set . m wq L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wk L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wv L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wo L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wg L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wu L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_slot_set . m wd L @ FtW { 0 0 ( vec_new [f] ) } )
    ( __ft_vslot_set . m an L # s 0 )
    ( __ft_vslot_set . m fn L # s 0 )
    ( __ft_vslot_set . m qn L # s 0 )
    ( __ft_vslot_set . m kn L # s 0 )
}

// Fill every lazy base const's device buffer. Call once, right after the
// capture; T when every tensor landed.
@ ft_stream_upload * FtModel m * GProg pg → b {
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
            ( gguf_close gg )
        }
        F e → { ( string_free e ) = ok F }
    }
    ^ ok
}

@ ft_train * FtModel m ( Vec i ) corpus i win i r f alpha i seed i steps f lr i dtype b verbose → FtTrain {
    : i total ( vec_len [i] corpus )
    : ~ i T2 win
    ? > T2 total { = T2 total } {}
    : ~ i nwin / total T2
    ? < nwin 1 { = nwin 1 } {}
    : ( Vec i ) ids ( vec_with_cap [i] T2 )
    : ~ i k0 0
    ~ < k0 T2 { ( vec_push [i] ids ( _ti corpus k0 ) ) = k0 + k0 1 }
    : i nslot * 7 . m n_layer
    : *u pids ( nurl_alloc * * 2 nslot 8 )
    // ft_graph needs the base matrices; a prior ft_train may have dropped
    // them (they only live host-side to build the graph). Stream them back.
    ? == ( vec_len [FtW] . m wq ) 0 { : b _r ( ft_reload_base m ) } {}
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
        : *GProg pg ( gput_capture_dt kit tp . fg loss dtype )
        = ok ( gput_ok pg )
        // streamed base: the capture allocated the buffers from the shapes,
        // now fill them one tensor at a time
        ? ok { = ok ( ft_stream_upload m pg ) } {}
        // The base weights are now on the device; their f64 host copies are
        // dead weight during training. Free BOTH the tape's const nodes and
        // the model's per-layer base matrices — host RAM drops to the
        // adapters + activations. The base streams back from the GGUF for the
        // merge (ft_reload_base). Training reads device buffers only.
        ? ok { ( tape_drop_consts tp ) ( ft_drop_base m ) } {}
        : *GpOpt go ( gpopt_adam_new lr )
        : ~ i pi 0
        ~ < pi * 2 nslot {
            ( gpopt_add go pg @ GVar { ( nurl_peek pids pi ) } 0.0 )
            = pi + pi 1
        }
        : ~ i cur 0
        : ~ i st 0
        ~ & < st steps ok {
            // round-robin window switch: refresh the two input consts
            : i w % st nwin
            ? & > nwin 1 != w cur {
                : ( Vec i ) wids ( vec_with_cap [i] T2 )
                : ~ i q 0
                ~ < q T2 { ( vec_push [i] wids ( _ti corpus + * w T2 q ) ) = q + q 1 }
                : ( Vec f ) xr ( ft_embed m wids )
                = ok & ok ( gput_set_input pg . fg xin xr )
                ( vec_free [f] xr )
                : ( Vec f ) ohr ( ft_onehot m wids )
                = ok & ok ( gput_set_input pg . fg ohin ohr )
                ( vec_free [f] ohr )
                ( vec_free [i] wids )
                = cur w
            } {}
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
    ( vec_free [i] ids )
    ^ @ FtTrain { ok l0 l1 aflat bflat }
}

// ── safetensors output (via the safetensor package's writer) ─────────

// Add one F32 tensor with shape [d0] (d1==0) or [d0,d1].
@ __ft_st_add * StWriter w s name ( Vec f ) v i d0 i d1 → v {
    : ( Vec i ) sh ( vec_new [i] )
    ( vec_push [i] sh d0 )
    ? > d1 0 { ( vec_push [i] sh d1 ) } {}
    ( stw_add_f32 w name sh v )
    ( vec_free [i] sh )
}

// Save trained adapters as a safetensors file: per slot,
// blk.<L>.<which>.lora_a [in,r] and .lora_b [r,out], F32.
@ ft_adapters_save s path * FtModel m FtTrain t i r → !v String {
    : *StWriter so ( stw_new )
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
        ( vec_free [f] av )
        : ( Vec f ) bv ( vec_with_cap [f] * r out )
        = k 0
        ~ < k * r out { ( vec_push [f] bv ( _tf . t bflat + boff k ) ) = k + k 1 }
        ( __ft_st_add so ( string_data nb ) bv r out )
        ( vec_free [f] bv )
        ( string_free na ) ( string_free nb )
        = aoff + aoff * in r
        = boff + boff * r out
        ? & . m stream == w 6 { ( __ft_layer_out m L ) } {}
        = sl + sl 1
    }
    ? . m stream {
        ? != . m mgg 0 {
            : *Gguf mgg2 # *Gguf . m mgg
            ( gguf_close mgg2 )
            = . m mgg 0
        } {}
    } {}
    : !v String res ( stw_write so path )
    ( stw_free so )
    ^ res
}

// ── merge: base + (α/r)·A·B → a full-weights safetensors file ────────
// nurllama's verified `--weights` path (llm_open_st) then runs the merged
// model with the GGUF supplying metadata + tokenizer. Weights are emitted
// [out, in] F32 under HF names in TRUE HF lane order — llm_open_st
// interleaves NORM-rope q/k at load, exactly like llama.cpp's converter
// does for GGUFs, so the file is a genuine HF checkpoint.

// merged tape-layout [in,out] → emit [out,in] rows; q/k: NORM re-permute.
@ __ft_emit_w * StWriter so s name FtW w b reperm i heads i hd → v {
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
    ( vec_free [f] e )
}

// Merge every adapter into its base weight and write the FULL model as a
// safetensors file — run it with nurllama's --weights path (llm_open_st).
@ ft_merge_st s path * FtModel m FtTrain t i r f alpha → !v String {
    ^ ( ft_merge_st_mask path m t r alpha 15 )
}

// mask bit0 = embeddings, bit1 = attention projections, bit2 = mlp
// projections (a bisect handle for the merged-path diagnostics).
@ ft_merge_st_mask s path * FtModel m FtTrain t i r f alpha i mask → !v String {
    : f scale / alpha # f r
    // The per-layer base matrices were freed after device capture
    // (ft_drop_base); stream them back for the merge (identical loader path,
    // so the NORM-rope un-permute matches byte-for-byte). No-op if resident.
    ? == ( vec_len [FtW] . m wq ) 0 {
        ? ( ft_reload_base m ) {} {
            ^ @ !v String { F ( string_from `finetune: cannot reload base weights for merge` ) }
        }
    } {}
    // A streamed model holds shape-only placeholders, so the check above
    // cannot see that the values are missing — merging them would write a
    // model of zeros. Hold the GGUF open and page one layer in at a time.
    ? . m stream {
        ?? ( gguf_open ( string_data . m src_path ) ) {
            T gg → { = . m mgg # i gg }
            F e → { ^ @ !v String { F e } }
        }
    } {}
    : *StWriter so ( stw_new )
    // embeddings + final norm (frozen; [V,H] is already [out,in])
    ? == % mask 2 1 {
        ( __ft_st_add so `model.embed_tokens.weight` . m embd . m n_vocab . m n_embd )
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
            : *Gguf mgg # *Gguf . m mgg
            : b _li ( __ft_layer_in mgg m L )
        } {}
        // the per-layer norms, once per layer (at slot 0; norm mask bit3)
        ? & == w 0 == % / mask 8 2 1 {
            : s anp ?? ( vec_get [s] . m an L ) { T x → x F → # s 0 }
            : *FtV anv # *FtV anp
            : String n1 ( string_from `model.layers.` )
            ( string_push_str n1 ( nurl_str_int L ) )
            ( string_push_str n1 `.input_layernorm.weight` )
            ( __ft_st_add so ( string_data n1 ) . anv v . m n_embd 0 )
            ( string_free n1 )
            : s fnp ?? ( vec_get [s] . m fn L ) { T x → x F → # s 0 }
            : *FtV fnv # *FtV fnp
            : String n2 ( string_from `model.layers.` )
            ( string_push_str n2 ( nurl_str_int L ) )
            ( string_push_str n2 `.post_attention_layernorm.weight` )
            ( __ft_st_add so ( string_data n2 ) . fnv v . m n_embd 0 )
            ( string_free n2 )
            // qwen3's per-head Q/K norms are frozen too, but a merged
            // model without them is a DIFFERENT model — emit when present.
            : s qnp ?? ( vec_get [s] . m qn L ) { T x → x F → # s 0 }
            ? != # i qnp 0 {
                : *FtV qnv # *FtV qnp
                : String n3 ( string_from `model.layers.` )
                ( string_push_str n3 ( nurl_str_int L ) )
                ( string_push_str n3 `.self_attn.q_norm.weight` )
                ( __ft_st_add so ( string_data n3 ) . qnv v . m head_dim 0 )
                ( string_free n3 )
            } {}
            : s knp ?? ( vec_get [s] . m kn L ) { T x → x F → # s 0 }
            ? != # i knp 0 {
                : *FtV knv # *FtV knp
                : String n4 ( string_from `model.layers.` )
                ( string_push_str n4 ( nurl_str_int L ) )
                ( string_push_str n4 `.self_attn.k_norm.weight` )
                ( __ft_st_add so ( string_data n4 ) . knv v . m head_dim 0 )
                ( string_free n4 )
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
                ( __ft_st_add so ( string_data nb ) . bv2 v out 0 )
                ( string_free nb )
            } {}
        } {}
        = aoff + aoff * in r
        = boff + boff * r out
        = sl + sl 1
    }
    : !v String res ( stw_write so path )
    ( stw_free so )
    ^ res
}

// ── the CLI driver ───────────────────────────────────────────────────
// nurllama finetune <model.gguf> <data.txt>: tokenize the corpus with the
// model's own tokenizer, LoRA-train on the DEVICE over the first `seq`
// tokens (v1 trains one fixed window — the captured graph has a fixed
// shape; multi-window scheduling lands with gput_set_input plumbing),
// save the adapters, and optionally write a merged full-model safetensors
// runnable via `nurllama run model.gguf PROMPT --weights merged.st`.
@ nurllama_finetune s modp s datap s outp s mergedp i steps f lr i rank f alpha i seq i seed b f32 b mixed → i {
    : ~ s text ``
    : ~ b haderr F
    : ~ String textS ( string_new )
    ?? ( read_file datap ) {
        T t → { ( string_free textS ) = textS t = text ( string_data textS ) }
        F _ → {
            ( nurl_eprintln `nurllama: cannot read the data file` )
            = haderr T
        }
    }
    ? haderr { ( string_free textS ) ^ 1 } {}
    : ( Vec i ) ids ( vec_new [i] )
    ?? ( gguf_open modp ) {
        T gg → {
            ?? ( tok_new gg ) {
                T tk → {
                    : ( Vec i ) enc ( tok_encode tk text T )
                    : ~ i k 0
                    ~ < k ( vec_len [i] enc ) { ( vec_push [i] ids ( _ti enc k ) ) = k + k 1 }
                    ( vec_free [i] enc )
                    ( tok_free tk )
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                    ( string_free e )
                    = haderr T
                }
            }
            ( gguf_close gg )
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            = haderr T
        }
    }
    ( string_free textS )
    ? | haderr < ( vec_len [i] ids ) 4 {
        ( vec_free [i] ids )
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
            ( nurl_print ( nurl_str_int . m n_layer ) )
            ( nurl_print ` layers · hidden ` )
            ( nurl_print ( nurl_str_int . m n_embd ) )
            ( nurl_print ` · building the tape + capturing onto the device\n` )
            : i dt ? mixed 2 ? f32 1 0
            ? mixed { ( nurl_print `precision: mixed (f32 storage, f64 accumulation — half VRAM, near-f64 accuracy)\n` ) } {}
            ? & f32 == mixed F { ( nurl_print `precision: float32 device replay (half VRAM; float32 precision, not bit-exact to f64)\n` ) } {}
            : FtTrain tr ( ft_train m ids seq rank alpha seed steps lr dt T )
            ? . tr ok {} {
                ( nurl_eprintln `nurllama: finetune training failed (no device? poisoned graph?)` )
                ( ft_train_free tr ) ( ft_free m ) ( vec_free [i] ids )
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
                    ( string_free e )
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
                        ( string_free e )
                        = rc 1
                    }
                }
            } {}
            ( ft_train_free tr )
            ( ft_free m )
            ( vec_free [i] ids )
            ^ rc
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ( vec_free [i] ids )
            ^ 1
        }
    }
}
