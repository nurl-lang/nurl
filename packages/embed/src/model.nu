// packages/embed/src/model.nu — the XLM-RoBERTa-family text encoder,
// pure NURL on gpukit's dev-layer kernel library.
//
// This is the model class behind BGE-M3, multilingual-e5 and friends:
// word/position/type embeddings + LayerNorm, N transformer blocks
// (bidirectional self-attention, exact-erf GELU FFN, post-LN residuals),
// then CLS or mean pooling and an optional L2 normalize. Every operator
// is a gkd_* kernel — the same dtype-generic library tensor and onnx run
// on — so this file contains NO kernel sources, only the wiring.
//
// A model is a DIRECTORY (the Hugging Face layout):
//   config.json         hidden_size / num_hidden_layers / … (read here)
//   tokenizer.json      Unigram vocabulary (packages/tokenizer)
//   model.safetensors   f32 weights (packages/safetensor, mmap-backed)
//
//   ( embed_open dir )              → !*Embed String
//   ( embed_open_dev dir gpu )      → !*Embed String   (gpu -1 = best)
//   ( embed_encode e text out )     → b     out = the embedding vector
//   ( embed_encode_batch e ids offs out norm ) → b     B texts, one call
//   ( embed_dim e ) ( embed_close e )
//
// Inference is BATCHED where the fused attention runs (CUDA): texts are
// grouped longest-first into chunks of at most EM_ROWS_BUDGET padded
// device rows, and a chunk is ONE forward — every kernel sees all of its
// sequences at once, which is what turns thirty short texts from thirty
// launch-bound forwards into one. Sequences are padded to a quantised
// length, batches to a quantised count, and every bit of padding is
// masked out of attention and pooling (see __em_bucket) — the numbers
// are the numbers of the unpadded, unbatched run, and what the
// quantisation buys is a forward that stops compiling kernels and
// allocating device memory after the first few requests. On the CPU
// backend (or a head width the fused kernel refuses) each text runs
// alone through the composed path, exactly as before.
//
// Numerics are true float32 on the device. Verified against
// sentence-transformers (BGE-M3): cosine ≥ 0.9999 on a multilingual
// corpus (tests/embed_test.sh).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/ext/json.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/devops.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `deps/tokenizer/src/unigram.nu`

// pooling modes
: i EM_POOL_CLS 0
: i EM_POOL_MEAN 1

: EmbedCfg {
    i layers
    i heads
    i dim
    i ffn
    i vocab
    i maxpos  // position table rows (XLM-R: max_seq + pad offset 2)
    i padid
    f eps
    i pool
    b normalize
    i maxseq  // token cap per text (specials included)
}

: EmbedLayer {
    GkBuf qw GkBuf qb
    GkBuf kw GkBuf kb
    GkBuf vw GkBuf vb
    GkBuf ow GkBuf ob
    GkBuf ln1w GkBuf ln1b
    GkBuf iw GkBuf ib
    GkBuf dw GkBuf db
    GkBuf ln2w GkBuf ln2b
}

: Embed {
    * GpuKit kit
    EmbedCfg cfg
    GkBuf wemb
    GkBuf pemb
    GkBuf temb
    GkBuf elnw
    GkBuf elnb
    ( Vec EmbedLayer ) layers
    * Unigram tok
    b has_tok
    b ok
}

@ __em_err s msg → !*Embed String {
    ^ @ !*Embed String { F ( string_from msg ) }
}

@ __em_cfg_int Json root s key i def → i {
    ?? ( json_obj_get root key ) {
        T v → { ?? ( json_num_as_i v ) { T x → { ^ x } F → { ^ def } } }
        F → { ^ def }
    }
}

@ __em_cfg_f Json root s key f def → f {
    ?? ( json_obj_get root key ) {
        T v → { ?? ( json_num_as_f v ) { T x → { ^ x } F → { ^ def } } }
        F → { ^ def }
    }
}

// Upload one f32 tensor from the mapping to the device. On any miss or
// dtype surprise the engine is marked broken and an empty buf returned —
// nothing runs on a partially-loaded model.
@ __em_up * Embed e * St s2 s name → GkBuf {
    : i idx ( st_find_tensor s2 name )
    ? >= idx 0 {} { = . e ok F ^ @ GkBuf { 0 0 GK_F32 } }
    ?? ( vec_get [StTensor] . s2 tensors idx ) {
        T t → {
            ? == . t dtype ST_F32 {} { = . e ok F ^ @ GkBuf { 0 0 GK_F32 } }
            : GkBuf b ( gk_dbuf_new . e kit . t nelems GK_F32 )
            ? ( gk_buf_ok b ) {} { = . e ok F ^ b }
            : GpuBuffer gb @ GpuBuffer { . b dptr * . t nelems 4 }
            ? == ( gpu_upload gb ( st_tensor_ptr s2 t ) ) 0 {} { = . e ok F }
            ^ b
        }
        F → { = . e ok F ^ @ GkBuf { 0 0 GK_F32 } }
    }
}

// model-relative path: dir + "/" + leaf (caller frees)
@ __em_path s dir s leaf → String {
    : String p ( string_from dir )
    : i dn ( nurl_str_len dir )
    ? & > dn 0 != ( nurl_str_get dir - dn 1 ) 47 { ( string_push_char p 47 ) } {}
    ( string_push_str p leaf )
    ^ p
}

// encoder.layer.<L>.<suffix>
@ __em_lname i layer s suffix → String {
    : String s2 ( string_from `encoder.layer.` )
    ( string_push_int s2 layer )
    ( string_push_char s2 46 )
    ( string_push_str s2 suffix )
    ^ s2
}

@ __em_up_layer * Embed e * St s2 i layer s suffix → GkBuf {
    : String nm ( __em_lname layer suffix )
    : GkBuf b ( __em_up e s2 ( string_data nm ) )
    ( string_free nm )
    ^ b
}

// Open a model directory. Pooling defaults to CLS + normalize (the BGE
// convention); callers can override with embed_set_pooling.
@ embed_open s dir → !*Embed String {
    ^ ( embed_open_dev dir - 0 1 )
}

// The same, with the device chosen by the caller: `gpu` is a CUDA
// device ordinal (CUDA enumeration order — fastest first by default —
// not nvidia-smi's PCI order), or -1 for the best device / the
// $NURL_GPU_DEVICE override. A named ordinal must BE a CUDA device:
// falling back to the CPU backend behind an explicit --gpu would be
// hiding exactly the mistake the flag exists to make loud.
@ embed_open_dev s dir i gpu → !*Embed String {
    : *Embed e # *Embed ( nurl_alloc Z Embed )
    = . e ok T
    = . e has_tok F
    = . e layers ( vec_new [EmbedLayer] )
    // config.json
    : String cfgp ( __em_path dir `config.json` )
    : ~ b cfg_ok F
    ?? ( read_file ( string_data cfgp ) ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T root → {
                    : i dim ( __em_cfg_int root `hidden_size` 1024 )
                    : i heads ( __em_cfg_int root `num_attention_heads` 16 )
                    : i maxpos ( __em_cfg_int root `max_position_embeddings` 8194 )
                    : i padid ( __em_cfg_int root `pad_token_id` 1 )
                    = . e cfg @ EmbedCfg {
                        ( __em_cfg_int root `num_hidden_layers` 24 )
                        heads
                        dim
                        ( __em_cfg_int root `intermediate_size` 4096 )
                        ( __em_cfg_int root `vocab_size` 250002 )
                        maxpos
                        padid
                        ( __em_cfg_f root `layer_norm_eps` 0.00001 )
                        EM_POOL_CLS
                        T
                        - - maxpos padid 1  // XLM-R: usable positions
                    }
                    ? == % dim heads 0 { = cfg_ok T } {}
                    ( json_free root )
                }
                F _e → {}
            }
            ( string_free txt )
        }
        F _ → {}
    }
    ( string_free cfgp )
    ? cfg_ok {} { ( embed_close e ) ^ ( __em_err `embed: cannot read config.json (or dim % heads != 0)` ) }
    // tokenizer.json
    : String tokp ( __em_path dir `tokenizer.json` )
    : ~ String tokerr ( string_new )
    ?? ( uni_load ( string_data tokp ) ) {
        T u → { = . e tok u = . e has_tok T }
        F te → { ( string_free tokerr ) = tokerr te }
    }
    ( string_free tokp )
    ? . e has_tok {} {
        ( embed_close e )
        ^ @ !*Embed String { F tokerr }
    }
    ( string_free tokerr )
    // device: the one the caller named, else the BEST one — not driver
    // ordinal 0. On a box with an old card in front of a new one — a
    // 4 GB GTX 970 ahead of a 24 GB RTX 4090 — ordinal 0 is where 2.3 GB
    // of weights plus activations do not fit, and gk_open_best is
    // exactly the answer to that. $NURL_GPU_DEVICE still overrides the
    // default; an explicit `gpu` ordinal overrides everything.
    ? >= gpu 0 {
        = . e kit ( gk_open gpu )
        ? & ( gk_ok . e kit ) != 0 ( nurl_str_eq ( gk_backend . e kit ) `cuda` ) {} {
            ( embed_close e )
            ^ ( __em_err `embed: --gpu: not a usable CUDA device ordinal (note: CUDA order is fastest-first, not nvidia-smi's PCI order)` )
        }
    } {
        = . e kit ( gk_open_best )
        ? ( gk_ok . e kit ) {} { ( embed_close e ) ^ ( __em_err `embed: no compute device (CUDA or CPU backend)` ) }
    }
    // weights
    : String stp ( __em_path dir `model.safetensors` )
    : ~ b st_ok F
    ?? ( st_open ( string_data stp ) ) {
        T s2 → {
            = st_ok T
            = . e wemb ( __em_up e s2 `embeddings.word_embeddings.weight` )
            = . e pemb ( __em_up e s2 `embeddings.position_embeddings.weight` )
            = . e temb ( __em_up e s2 `embeddings.token_type_embeddings.weight` )
            = . e elnw ( __em_up e s2 `embeddings.LayerNorm.weight` )
            = . e elnb ( __em_up e s2 `embeddings.LayerNorm.bias` )
            : ~ i l 0
            ~ & . e ok < l . . e cfg layers {
                : EmbedLayer lay @ EmbedLayer {
                    ( __em_up_layer e s2 l `attention.self.query.weight` )
                    ( __em_up_layer e s2 l `attention.self.query.bias` )
                    ( __em_up_layer e s2 l `attention.self.key.weight` )
                    ( __em_up_layer e s2 l `attention.self.key.bias` )
                    ( __em_up_layer e s2 l `attention.self.value.weight` )
                    ( __em_up_layer e s2 l `attention.self.value.bias` )
                    ( __em_up_layer e s2 l `attention.output.dense.weight` )
                    ( __em_up_layer e s2 l `attention.output.dense.bias` )
                    ( __em_up_layer e s2 l `attention.output.LayerNorm.weight` )
                    ( __em_up_layer e s2 l `attention.output.LayerNorm.bias` )
                    ( __em_up_layer e s2 l `intermediate.dense.weight` )
                    ( __em_up_layer e s2 l `intermediate.dense.bias` )
                    ( __em_up_layer e s2 l `output.dense.weight` )
                    ( __em_up_layer e s2 l `output.dense.bias` )
                    ( __em_up_layer e s2 l `output.LayerNorm.weight` )
                    ( __em_up_layer e s2 l `output.LayerNorm.bias` )
                }
                ( vec_push [EmbedLayer] . e layers lay )
                = l + l 1
            }
            ( st_close s2 )
        }
        F se → { ( string_free se ) }
    }
    ( string_free stp )
    ? & st_ok . e ok {} {
        ( embed_close e )
        ^ ( __em_err `embed: model.safetensors missing, or a tensor absent / not f32` )
    }
    ^ @ !*Embed String { T e }
}

// Pooling override: mode EM_POOL_CLS | EM_POOL_MEAN, normalize on/off.
// (cfg is an inline struct; a field write through two levels is not an
// lvalue in NURL, so the setters rebuild the struct.)
@ embed_set_pooling * Embed e i mode b normalize → v {
    : EmbedCfg c . e cfg
    = . e cfg @ EmbedCfg { . c layers . c heads . c dim . c ffn . c vocab . c maxpos . c padid . c eps mode normalize . c maxseq }
}

// Cap on tokens per text (specials included); clamped to the model's
// position table.
@ embed_set_maxseq * Embed e i n → v {
    : EmbedCfg c . e cfg
    : i lim - - . c maxpos . c padid 1
    ? & > n 0 <= n lim {
        = . e cfg @ EmbedCfg { . c layers . c heads . c dim . c ffn . c vocab . c maxpos . c padid . c eps . c pool . c normalize n }
    } {}
}

@ embed_dim * Embed e → i { ^ . . e cfg dim }

@ embed_ok * Embed e → b { ^ . e ok }

@ embed_backend * Embed e → s { ^ ( gk_backend . e kit ) }

@ embed_device_name * Embed e → s { ^ ( gk_device_name . e kit ) }

@ embed_maxseq * Embed e → i { ^ . . e cfg maxseq }

@ __em_free_buf GkBuf b → v { ( gk_dbuf_free b ) }

@ embed_close * Embed e → v {
    ( __em_free_buf . e wemb ) ( __em_free_buf . e pemb ) ( __em_free_buf . e temb )
    ( __em_free_buf . e elnw ) ( __em_free_buf . e elnb )
    : i n ( vec_len [EmbedLayer] . e layers )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [EmbedLayer] . e layers k ) {
            T l → {
                ( __em_free_buf . l qw ) ( __em_free_buf . l qb )
                ( __em_free_buf . l kw ) ( __em_free_buf . l kb )
                ( __em_free_buf . l vw ) ( __em_free_buf . l vb )
                ( __em_free_buf . l ow ) ( __em_free_buf . l ob )
                ( __em_free_buf . l ln1w ) ( __em_free_buf . l ln1b )
                ( __em_free_buf . l iw ) ( __em_free_buf . l ib )
                ( __em_free_buf . l dw ) ( __em_free_buf . l db )
                ( __em_free_buf . l ln2w ) ( __em_free_buf . l ln2b )
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free [EmbedLayer] . e layers )
    ? . e has_tok { ( uni_free . e tok ) } {}
    ? != # i . e kit 0 { ( gk_close . e kit ) } {}
    ( nurl_free # *u e )
}

// ── forward ──────────────────────────────────────────────────────────

// The padded length a sequence of `n` tokens actually runs at.
//
// Every buffer and every shape-specialised kernel in the forward is a
// function of the sequence length, and BOTH are cached by shape: gpukit
// pools device blocks by exact byte size, and gkd_perm bakes its dims
// into the kernel name. Run one text per length and the cache is a
// ratchet — an NVRTC compile per new length (measured: 350 ms of the
// 385 ms a "cold" request took, against 36 ms warm) and a pool that
// grew from 4 GB to 10.8 GB over two hundred requests, until the driver
// refused and the whole pool was dumped and re-allocated. From outside
// that reads as the model being offloaded and loaded again.
//
// So the length is quantised: four steps per octave, i.e. at most 25%
// padding for anything past 32 tokens, and about forty distinct lengths
// over the model's whole 8192-token range. The padding is not free —
// the linear layers do run on it — but 25% of a 36 ms forward is 9 ms
// against the 350 ms stall it removes, and after the first few requests
// a server compiles nothing and allocates nothing at all.
//
// Padding is only sound because it is masked: see __em_attn.
@ __em_bucket i n → i {
    ? <= n 8 { ^ 8 } {}
    : ~ i p 8
    ~ <= * p 2 n { = p * p 2 }
    : ~ i step / p 4
    ? < step 8 { = step 8 } {}
    ^ * / + n - step 1 step step
}

// The batch count a chunk of `n` sequences actually runs at — the same
// four-steps-per-octave quantisation as __em_bucket, floored at 1, for
// the same reason: buffer sizes are a function of rows = batch·np, and
// a pool keyed by exact byte size wants FEW distinct row counts, not one
// per request shape. The filler is whole dummy sequences (all padding,
// fully masked, pooled by a zero weight row), at most 25% of the chunk.
@ __em_bucket_b i n → i {
    ? <= n 2 { ^ n } {}
    : ~ i p 2
    ~ <= * p 2 n { = p * p 2 }
    : ~ i step / p 4
    ? < step 1 { = step 1 } {}
    ^ * / + n - step 1 step step
}

// A fused-attention chunk holds at most this many padded device rows
// (batch · padded length). 16384 rows of BGE-M3 activations peak around
// 1.5 GB of pooled device buffers — and two full-length 8192-token
// texts still share one forward.
: i EM_ROWS_BUDGET 16384

// … and at most this many sequences, so a flood of tiny texts still
// produces a forward whose per-sequence host work (padding, masks,
// pooling rows) stays a rounding error.
: i EM_BATCH_MAX 64

// vec_get with a default — index arithmetic below is all pre-validated,
// so a miss is unreachable; 0 keeps the type checker honest.
@ __em_vi ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ 0 } }
}

@ __em_vf ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// token count of text `t` in a flat ids+offsets batch
@ __em_len ( Vec i ) offs i t → i {
    ^ - ( __em_vi offs + t 1 ) ( __em_vi offs t )
}

// y[n,dim] = x[n,in] · W[dim,in]ᵀ + bias — the HF Linear shape.
@ __em_linear * Embed e GkBuf y GkBuf x GkBuf w GkBuf bb i n i dout i din → b {
    ^ ( gkd_gemm . e kit y x w bb 1 n dout din 1.0 1.0 1 )
}

// exact-erf GELU, in place semantics via a fresh output buffer
@ __em_gelu * Embed e GkBuf y GkBuf x → b {
    ^ ( gkd_map . e kit `geluerf` `x*0.5f*(1.0f+erff(x*0.70710678f))` y x )
}

@ __em_new * Embed e i nfloats → GkBuf {
    ^ ( gk_dbuf_new . e kit nfloats GK_F32 )
}

// "Effectively −∞" as an additive score bias: large enough that
// expf(bias − max) is exactly 0 in f32, small enough to stay finite.
// (NURL has no exponent float literal, so it is built, once, here.)
@ __em_neg_inf → f { ^ - 0.0 ( float_pow 10.0 30.0 ) }

// Scaled dot-product attention over q/k/v laid out [heads, n, hd], with
// `mask` a per-key additive bias of n floats shared by every head (0 for
// a real token, −1e30 for padding).
//
// The masked key never enters the row maximum and contributes exactly
// zero to the denominator, so a padded row of keys leaves every real
// row's output the row it would have had without the padding — that is
// what makes the quantised length above a change of shape only, not of
// numbers.
//
// The fused kernel is preferred: it never materialises [heads, n, n],
// which at 8192 tokens is 4.3 GB per buffer and was the reason a long
// text needed several gigabytes of scratch. Where it will not run (the
// CPU backend, or a head width its register tile is not sized for) the
// composed bmm/softmax/bmm path runs instead, with the same mask added
// to the scores.
@ __em_attn * Embed e GkBuf ctx GkBuf qh GkBuf kh GkBuf vh GkBuf mask i n → b {
    : i dim . . e cfg dim
    : i heads . . e cfg heads
    : i hd / dim heads
    : f scale / 1.0 ( float_sqrt # f hd )
    ? ( gkd_attention_ok . e kit hd ) {
        ^ ( gkd_attention_masked . e kit ctx qh kh vh mask heads n n hd heads scale )
    } {}
    : ~ b ok T
    // kt[heads, hd, n]
    : GkBuf kt ( __em_new e * n dim )
    : ( Vec i ) d3 ( vec_new [i] )
    ( vec_push [i] d3 heads ) ( vec_push [i] d3 n ) ( vec_push [i] d3 hd )
    : ( Vec i ) p021 ( vec_new [i] )
    ( vec_push [i] p021 0 ) ( vec_push [i] p021 2 ) ( vec_push [i] p021 1 )
    = ok ( gkd_perm . e kit kt kh d3 p021 )
    : GkBuf sc ( __em_new e * * heads n n )
    ? ok { = ok ( gkd_bmm . e kit sc qh kt heads n hd n 1 1 ) } {}
    // scale, then the mask — both in place: every one of these is an
    // elementwise write whose input index IS its output index.
    : GkBuf inv ( __em_new e 1 )
    : ( Vec f ) hinv ( vec_new [f] )
    ( vec_push [f] hinv scale )
    ? ok { = ok ( gk_dbuf_upload . e kit inv hinv ) } {}
    ( vec_free [f] hinv )
    ? ok { = ok ( gkd_mul . e kit sc sc inv ) } {}
    : ( Vec i ) od ( vec_new [i] )
    ( vec_push [i] od * heads n ) ( vec_push [i] od n )
    : ( Vec i ) sa ( vec_new [i] )
    ( vec_push [i] sa n ) ( vec_push [i] sa 1 )
    : ( Vec i ) sb ( vec_new [i] )
    ( vec_push [i] sb 0 ) ( vec_push [i] sb 1 )
    ? ok { = ok ( gkd_ew_bc . e kit `add` `+` sc sc mask od sa sb ) } {}
    : GkBuf pr ( __em_new e * * heads n n )
    ? ok { = ok ( gkd_softmax_ax . e kit pr sc * heads n n 1 ) } {}
    ? ok { = ok ( gkd_bmm . e kit ctx pr vh heads n n hd 1 1 ) } {}
    ( gk_dbuf_free kt ) ( gk_dbuf_free sc ) ( gk_dbuf_free inv ) ( gk_dbuf_free pr )
    ( vec_free [i] d3 ) ( vec_free [i] p021 )
    ( vec_free [i] od ) ( vec_free [i] sa ) ( vec_free [i] sb )
    ^ ok
}

// One transformer block over hidden[n,dim] (replaces `hid` content by
// writing into it at the residual+LN steps). Returns F on any failure.
@ __em_block * Embed e EmbedLayer l GkBuf hid GkBuf mask i n → b {
    : i dim . . e cfg dim
    : i heads . . e cfg heads
    : i hd / dim heads
    : i ffn . . e cfg ffn
    : f eps . . e cfg eps
    : ~ b ok T
    : GkBuf q ( __em_new e * n dim )
    : GkBuf k ( __em_new e * n dim )
    : GkBuf v ( __em_new e * n dim )
    ? ok { = ok ( __em_linear e q hid . l qw . l qb n dim dim ) } {}
    ? ok { = ok ( __em_linear e k hid . l kw . l kb n dim dim ) } {}
    ? ok { = ok ( __em_linear e v hid . l vw . l vb n dim dim ) } {}
    // heads: [n,heads,hd] → [heads,n,hd] for all three
    : GkBuf qh ( __em_new e * n dim )
    : GkBuf kh ( __em_new e * n dim )
    : GkBuf vh ( __em_new e * n dim )
    : ( Vec i ) dims ( vec_new [i] )
    ( vec_push [i] dims n ) ( vec_push [i] dims heads ) ( vec_push [i] dims hd )
    : ( Vec i ) p102 ( vec_new [i] )
    ( vec_push [i] p102 1 ) ( vec_push [i] p102 0 ) ( vec_push [i] p102 2 )
    ? ok { = ok ( gkd_perm . e kit qh q dims p102 ) } {}
    ? ok { = ok ( gkd_perm . e kit kh k dims p102 ) } {}
    ? ok { = ok ( gkd_perm . e kit vh v dims p102 ) } {}
    : GkBuf ctx ( __em_new e * n dim )
    ? ok { = ok ( __em_attn e ctx qh kh vh mask n ) } {}
    // merge the heads back: [heads,n,hd] → [n,heads,hd]
    : GkBuf mrg ( __em_new e * n dim )
    : ( Vec i ) dims2 ( vec_new [i] )
    ( vec_push [i] dims2 heads ) ( vec_push [i] dims2 n ) ( vec_push [i] dims2 hd )
    ? ok { = ok ( gkd_perm . e kit mrg ctx dims2 p102 ) } {}
    // attention out + residual + LN
    : GkBuf ao ( __em_new e * n dim )
    ? ok { = ok ( __em_linear e ao mrg . l ow . l ob n dim dim ) } {}
    : GkBuf res ( __em_new e * n dim )
    ? ok { = ok ( gkd_add . e kit res ao hid ) } {}
    ? ok { = ok ( gkd_layernorm . e kit hid res . l ln1w . l ln1b n dim eps ) } {}
    // FFN + residual + LN
    : GkBuf h1 ( __em_new e * n ffn )
    ? ok { = ok ( __em_linear e h1 hid . l iw . l ib n ffn dim ) } {}
    : GkBuf h1g ( __em_new e * n ffn )
    ? ok { = ok ( __em_gelu e h1g h1 ) } {}
    : GkBuf h2 ( __em_new e * n dim )
    ? ok { = ok ( __em_linear e h2 h1g . l dw . l db n dim ffn ) } {}
    : GkBuf res2 ( __em_new e * n dim )
    ? ok { = ok ( gkd_add . e kit res2 h2 hid ) } {}
    ? ok { = ok ( gkd_layernorm . e kit hid res2 . l ln2w . l ln2b n dim eps ) } {}
    ( gk_dbuf_free q ) ( gk_dbuf_free k ) ( gk_dbuf_free v )
    ( gk_dbuf_free qh ) ( gk_dbuf_free kh ) ( gk_dbuf_free vh )
    ( gk_dbuf_free ctx ) ( gk_dbuf_free mrg )
    ( gk_dbuf_free ao ) ( gk_dbuf_free res )
    ( gk_dbuf_free h1 ) ( gk_dbuf_free h1g ) ( gk_dbuf_free h2 ) ( gk_dbuf_free res2 )
    ( vec_free [i] dims ) ( vec_free [i] dims2 ) ( vec_free [i] p102 )
    ^ ok
}

// One transformer block over hidden[bq·np, dim] for a whole batch, on
// gkd_attention_batch — the fused attention that reads Q/K/V in the
// layout the linear layers produce ([token row, heads·hd] interleaved)
// and writes ctx back the same way. No head split, no merge, no
// gkd_perm anywhere: the eight permute round trips __em_block pays per
// block do not exist here, and neither does the 4-D permute kernel a
// batched split would have baked a fresh NVRTC compile for per
// (batch, length) pair. `mask` is [bq, np] additive rows, one per
// sequence.
@ __em_block_x * Embed e EmbedLayer l GkBuf hid GkBuf mask i bq i np → b {
    : i dim . . e cfg dim
    : i heads . . e cfg heads
    : i hd / dim heads
    : i ffn . . e cfg ffn
    : f eps . . e cfg eps
    : i rows * bq np
    : f scale / 1.0 ( float_sqrt # f hd )
    : ~ b ok T
    : GkBuf q ( __em_new e * rows dim )
    : GkBuf k ( __em_new e * rows dim )
    : GkBuf v ( __em_new e * rows dim )
    ? ok { = ok ( __em_linear e q hid . l qw . l qb rows dim dim ) } {}
    ? ok { = ok ( __em_linear e k hid . l kw . l kb rows dim dim ) } {}
    ? ok { = ok ( __em_linear e v hid . l vw . l vb rows dim dim ) } {}
    : GkBuf ctx ( __em_new e * rows dim )
    ? ok { = ok ( gkd_attention_batch . e kit ctx q k v mask bq heads np np hd scale ) } {}
    // attention out + residual + LN
    : GkBuf ao ( __em_new e * rows dim )
    ? ok { = ok ( __em_linear e ao ctx . l ow . l ob rows dim dim ) } {}
    : GkBuf res ( __em_new e * rows dim )
    ? ok { = ok ( gkd_add . e kit res ao hid ) } {}
    ? ok { = ok ( gkd_layernorm . e kit hid res . l ln1w . l ln1b rows dim eps ) } {}
    // FFN + residual + LN
    : GkBuf h1 ( __em_new e * rows ffn )
    ? ok { = ok ( __em_linear e h1 hid . l iw . l ib rows ffn dim ) } {}
    : GkBuf h1g ( __em_new e * rows ffn )
    ? ok { = ok ( __em_gelu e h1g h1 ) } {}
    : GkBuf h2 ( __em_new e * rows dim )
    ? ok { = ok ( __em_linear e h2 h1g . l dw . l db rows dim ffn ) } {}
    : GkBuf res2 ( __em_new e * rows dim )
    ? ok { = ok ( gkd_add . e kit res2 h2 hid ) } {}
    ? ok { = ok ( gkd_layernorm . e kit hid res2 . l ln2w . l ln2b rows dim eps ) } {}
    ( gk_dbuf_free q ) ( gk_dbuf_free k ) ( gk_dbuf_free v )
    ( gk_dbuf_free ctx ) ( gk_dbuf_free ao ) ( gk_dbuf_free res )
    ( gk_dbuf_free h1 ) ( gk_dbuf_free h1g ) ( gk_dbuf_free h2 ) ( gk_dbuf_free res2 )
    ^ ok
}

// Tokenize (Unigram, <s>…</s>) with truncation to cfg.maxseq: the head
// of the sequence is kept and </s> re-appended, sentence-transformers
// style.
@ embed_tokenize * Embed e s text ( Vec i ) out → b {
    ? ( uni_encode . e tok text T out ) {} { ^ F }
    : i cap . . e cfg maxseq
    ? > ( vec_len [i] out ) cap {
        : i eos ( uni_eos . e tok )
        : ~ b okt T
        ~ & okt > ( vec_len [i] out ) - cap 1 {
            ?? ( vec_pop [i] out ) { T _ → {} F → { = okt F } }
        }
        ? & okt >= eos 0 { ( vec_push [i] out eos ) } {}
    } {}
    ^ T
}

// The embedding for one text, normalized per the engine's configuration.
// `out` receives embed_dim floats.
@ embed_encode * Embed e s text ( Vec f ) out → b {
    ^ ( embed_encode_norm e text out . . e cfg normalize )
}

// The same, with the L2 normalize decided by the caller — a request
// carrying "normalize": false must not have to reconfigure the engine
// (and a concurrent server must not be able to observe it doing so).
@ embed_encode_norm * Embed e s text ( Vec f ) out b normalize → b {
    ? . e ok {} { ^ F }
    : ( Vec i ) ids ( vec_new [i] )
    ? ( embed_tokenize e text ids ) {} { ( vec_free [i] ids ) ^ F }
    : b r ( embed_encode_ids_norm e ids out normalize )
    ( vec_free [i] ids )
    ^ r
}

@ embed_encode_ids * Embed e ( Vec i ) ids ( Vec f ) out → b {
    ^ ( embed_encode_ids_norm e ids out . . e cfg normalize )
}

// The single-text forward on the composed/permute path — what runs
// where the fused batch attention will not (the CPU backend, a head
// width gkd_attention_ok refuses). Reads ids[from .. from+n) and writes
// its dim floats into out at row `orow`. Callers hold the device bound
// and `e` verified.
@ __em_fwd_one * Embed e ( Vec i ) ids i from i n ( Vec f ) out i orow b normalize → b {
    ? > n 0 {} { ^ F }
    : i dim . . e cfg dim
    : i padid . . e cfg padid
    : i lim - - . . e cfg maxpos padid 1
    : ~ i np ( __em_bucket n )
    ? > np lim { = np lim } {}
    ? >= np n {} { ^ F }
    : ~ b ok T
    // chain launches; one sync at the end of the walk
    ( gk_autosync F )
    // ids to the device, padded out to the bucket with the pad token
    : ( Vec i ) pids ( vec_with_cap [i] np )
    : ~ i k 0
    ~ < k np {
        ( vec_push [i] pids ? < k n {
            ?? ( vec_get [i] ids + from k ) { T x → x F → padid }
        } { padid } )
        = k + k 1
    }
    : GkBuf idb ( gk_dbuf_new . e kit np GK_I64 )
    = ok ( gk_dbuf_upload_i . e kit idb pids )
    ( vec_free [i] pids )
    // the additive attention mask: 0 for a real token, −∞ for padding
    : GkBuf mask ( __em_new e np )
    : ( Vec f ) hmask ( vec_with_cap [f] np )
    : f ninf ( __em_neg_inf )
    = k 0
    ~ < k np { ( vec_push [f] hmask ? < k n { 0.0 } { ninf } ) = k + k 1 }
    ? ok { = ok ( gk_dbuf_upload . e kit mask hmask ) } {}
    ( vec_free [f] hmask )
    // hidden = word[ids] + positions[pad+1 .. pad+1+np) + type0
    : GkBuf hid ( __em_new e * np dim )
    ? ok { = ok ( gkd_gather . e kit hid . e wemb idb 1 . . e cfg vocab dim np ) } {}
    : GkBuf pos ( __em_new e * np dim )
    ? ok { = ok ( gkd_slice_ax . e kit pos . e pemb 1 np dim . . e cfg maxpos + padid 1 ) } {}
    : GkBuf sum1 ( __em_new e * np dim )
    ? ok { = ok ( gkd_add . e kit sum1 hid pos ) } {}
    // + token_type_embeddings[0] broadcast over rows
    : GkBuf sum2 ( __em_new e * np dim )
    : ( Vec i ) od ( vec_new [i] )
    ( vec_push [i] od np ) ( vec_push [i] od dim )
    : ( Vec i ) sa ( vec_new [i] )
    ( vec_push [i] sa dim ) ( vec_push [i] sa 1 )
    : ( Vec i ) sb ( vec_new [i] )
    ( vec_push [i] sb 0 ) ( vec_push [i] sb 1 )
    ? ok { = ok ( gkd_ew_bc . e kit `add` `+` sum2 sum1 . e temb od sa sb ) } {}
    ( vec_free [i] od ) ( vec_free [i] sa ) ( vec_free [i] sb )
    ? ok { = ok ( gkd_layernorm . e kit hid sum2 . e elnw . e elnb np dim . . e cfg eps ) } {}
    ( gk_dbuf_free pos ) ( gk_dbuf_free sum1 ) ( gk_dbuf_free sum2 )
    // blocks
    : i nl ( vec_len [EmbedLayer] . e layers )
    : ~ i l 0
    ~ & ok < l nl {
        ?? ( vec_get [EmbedLayer] . e layers l ) {
            T lay → { = ok ( __em_block e lay hid mask np ) }
            F → { = ok F }
        }
        = l + l 1
    }
    // Pooling is one row-weight vector times the hidden states: a
    // one-hot at row 0 is CLS, 1-over-the-real-rows is the mean, and
    // padding weighs 0 either way. Written as a single [1,np]x[np,dim]
    // gemm it is bit-identical to the slice-row-0 / scaled-ones-row
    // forms it replaces — adding an exact 0.0 to a running f32 sum
    // changes nothing, and the alpha is applied to the finished sum.
    : GkBuf pooled ( __em_new e dim )
    : GkBuf pw ( __em_new e np )
    : b meanpool == . . e cfg pool EM_POOL_MEAN
    : ( Vec f ) hpw ( vec_with_cap [f] np )
    = k 0
    ~ < k np {
        ( vec_push [f] hpw ? meanpool
        { ? < k n { 1.0 } { 0.0 } }
        { ? == k 0 { 1.0 } { 0.0 } } )
        = k + k 1
    }
    ? ok { = ok ( gk_dbuf_upload . e kit pw hpw ) } {}
    ( vec_free [f] hpw )
    ? ok {
        = ok ( gkd_gemm . e kit pooled pw hid pooled 0 1 dim np
        ? meanpool { / 1.0 # f n } { 1.0 } 0.0 0 )
    } {}
    ( gk_autosync T )
    // download + optional L2 normalize on the host, into out row `orow`
    : ( Vec f ) hp ( vec_with_cap [f] dim )
    : ~ i k2 0
    ~ < k2 dim { ( vec_push [f] hp 0.0 ) = k2 + k2 1 }
    ? ok { = ok ( gk_dbuf_download . e kit pooled hp ) } {}
    ? ok {
        : ~ f ss 0.0
        ? normalize {
            = k2 0
            ~ < k2 dim {
                : f x ( __em_vf hp k2 )
                = ss + ss * x x
                = k2 + k2 1
            }
        } {}
        : f nrm ( float_sqrt ss )
        : b div & normalize > nrm 0.0
        = k2 0
        ~ < k2 dim {
            : f x ( __em_vf hp k2 )
            ( vec_set [f] out + * orow dim k2 ? div { / x nrm } { x } )
            = k2 + k2 1
        }
    } {}
    ( vec_free [f] hp )
    ( gk_dbuf_free idb ) ( gk_dbuf_free mask ) ( gk_dbuf_free hid )
    ( gk_dbuf_free pooled ) ( gk_dbuf_free pw )
    ^ ok
}

// One padded, masked, fused forward over `take` real texts —
// ord[at .. at+take), longest first — plus (bq − take) dummy sequences,
// every sequence at padded length np. The dummies exist for the buffer
// pool (see __em_bucket_b); their rows run the arithmetic and are then
// pooled by an all-zero weight row and never copied out. Each real
// text's vector lands in `out` at its ORIGINAL index — ord carries it.
@ __em_fwd_batch * Embed e ( Vec i ) ids ( Vec i ) offs ( Vec i ) ord i at i take i bq i np b normalize ( Vec f ) out → b {
    : i dim . . e cfg dim
    : i padid . . e cfg padid
    : i rows * bq np
    : ~ b ok T
    ( gk_autosync F )
    // token ids, each sequence padded to np (dummies all padding)
    : ( Vec i ) pids ( vec_with_cap [i] rows )
    : ~ i bi 0
    ~ < bi bq {
        : b real < bi take
        : i n ? real { ( __em_len offs ( __em_vi ord + at bi ) ) } { 0 }
        : i o0 ? real { ( __em_vi offs ( __em_vi ord + at bi ) ) } { 0 }
        : ~ i k 0
        ~ < k np {
            ( vec_push [i] pids ? < k n { ( __em_vi ids + o0 k ) } { padid } )
            = k + k 1
        }
        = bi + bi 1
    }
    : GkBuf idb ( gk_dbuf_new . e kit rows GK_I64 )
    = ok ( gk_dbuf_upload_i . e kit idb pids )
    ( vec_free [i] pids )
    // the additive attention mask, one row per sequence: 0 for a real
    // token, −∞ for padding (a dummy is −∞ across; see gkd_attention_batch)
    : GkBuf mask ( __em_new e rows )
    : ( Vec f ) hmask ( vec_with_cap [f] rows )
    : f ninf ( __em_neg_inf )
    = bi 0
    ~ < bi bq {
        : i n ? < bi take { ( __em_len offs ( __em_vi ord + at bi ) ) } { 0 }
        : ~ i k 0
        ~ < k np { ( vec_push [f] hmask ? < k n { 0.0 } { ninf } ) = k + k 1 }
        = bi + bi 1
    }
    ? ok { = ok ( gk_dbuf_upload . e kit mask hmask ) } {}
    ( vec_free [f] hmask )
    // hidden = word[ids] + positions[pad+1 .. pad+1+np) + type0, LN —
    // the position table is one [np,dim] slice broadcast over the batch
    : GkBuf hid ( __em_new e * rows dim )
    ? ok { = ok ( gkd_gather . e kit hid . e wemb idb 1 . . e cfg vocab dim rows ) } {}
    : GkBuf pos ( __em_new e * np dim )
    ? ok { = ok ( gkd_slice_ax . e kit pos . e pemb 1 np dim . . e cfg maxpos + padid 1 ) } {}
    : GkBuf sum1 ( __em_new e * rows dim )
    : ( Vec i ) od1 ( vec_new [i] )
    ( vec_push [i] od1 bq ) ( vec_push [i] od1 * np dim )
    : ( Vec i ) sa1 ( vec_new [i] )
    ( vec_push [i] sa1 * np dim ) ( vec_push [i] sa1 1 )
    : ( Vec i ) sb1 ( vec_new [i] )
    ( vec_push [i] sb1 0 ) ( vec_push [i] sb1 1 )
    ? ok { = ok ( gkd_ew_bc . e kit `add` `+` sum1 hid pos od1 sa1 sb1 ) } {}
    ( vec_free [i] od1 ) ( vec_free [i] sa1 ) ( vec_free [i] sb1 )
    // + token_type_embeddings[0] broadcast over every row
    : GkBuf sum2 ( __em_new e * rows dim )
    : ( Vec i ) od ( vec_new [i] )
    ( vec_push [i] od rows ) ( vec_push [i] od dim )
    : ( Vec i ) sa ( vec_new [i] )
    ( vec_push [i] sa dim ) ( vec_push [i] sa 1 )
    : ( Vec i ) sb ( vec_new [i] )
    ( vec_push [i] sb 0 ) ( vec_push [i] sb 1 )
    ? ok { = ok ( gkd_ew_bc . e kit `add` `+` sum2 sum1 . e temb od sa sb ) } {}
    ( vec_free [i] od ) ( vec_free [i] sa ) ( vec_free [i] sb )
    ? ok { = ok ( gkd_layernorm . e kit hid sum2 . e elnw . e elnb rows dim . . e cfg eps ) } {}
    ( gk_dbuf_free pos ) ( gk_dbuf_free sum1 ) ( gk_dbuf_free sum2 )
    // blocks
    : i nl ( vec_len [EmbedLayer] . e layers )
    : ~ i l 0
    ~ & ok < l nl {
        ?? ( vec_get [EmbedLayer] . e layers l ) {
            T lay → { = ok ( __em_block_x e lay hid mask bq np ) }
            F → { = ok F }
        }
        = l + l 1
    }
    // Pooling: one weight row of np floats per sequence — a one-hot at
    // row 0 for CLS, ones over the real rows for mean, all zero for a
    // dummy — as a [bq,1,np]·[bq,np,dim] bmm. The mean's 1/n is applied
    // to the FINISHED sum as a per-sequence multiply, exactly where the
    // single-text path's gemm alpha put it, so the value is bit-identical.
    : GkBuf pooled ( __em_new e * bq dim )
    : GkBuf pw ( __em_new e rows )
    : b meanpool == . . e cfg pool EM_POOL_MEAN
    : ( Vec f ) hpw ( vec_with_cap [f] rows )
    = bi 0
    ~ < bi bq {
        : b real < bi take
        : i n ? real { ( __em_len offs ( __em_vi ord + at bi ) ) } { 0 }
        : ~ i k 0
        ~ < k np {
            : b on ? meanpool { < k n } { & real == k 0 }
            ( vec_push [f] hpw ? on { 1.0 } { 0.0 } )
            = k + k 1
        }
        = bi + bi 1
    }
    ? ok { = ok ( gk_dbuf_upload . e kit pw hpw ) } {}
    ( vec_free [f] hpw )
    ? ok { = ok ( gkd_bmm . e kit pooled pw hid bq 1 np dim 1 1 ) } {}
    ? & ok meanpool {
        : GkBuf inv ( __em_new e bq )
        : ( Vec f ) hinv ( vec_with_cap [f] bq )
        = bi 0
        ~ < bi bq {
            : i n ? < bi take { ( __em_len offs ( __em_vi ord + at bi ) ) } { 1 }
            ( vec_push [f] hinv / 1.0 # f ? > n 0 { n } { 1 } )
            = bi + bi 1
        }
        = ok ( gk_dbuf_upload . e kit inv hinv )
        ( vec_free [f] hinv )
        : ( Vec i ) odm ( vec_new [i] )
        ( vec_push [i] odm bq ) ( vec_push [i] odm dim )
        : ( Vec i ) sam ( vec_new [i] )
        ( vec_push [i] sam dim ) ( vec_push [i] sam 1 )
        : ( Vec i ) sbm ( vec_new [i] )
        ( vec_push [i] sbm 1 ) ( vec_push [i] sbm 0 )
        ? ok { = ok ( gkd_ew_bc . e kit `mul` `*` pooled pooled inv odm sam sbm ) } {}
        ( vec_free [i] odm ) ( vec_free [i] sam ) ( vec_free [i] sbm )
        ( gk_dbuf_free inv )
    } {}
    ( gk_autosync T )
    // download, then normalize + scatter each real row to its text's slot
    : ( Vec f ) hp ( vec_with_cap [f] * bq dim )
    : ~ i z 0
    ~ < z * bq dim { ( vec_push [f] hp 0.0 ) = z + z 1 }
    ? ok { = ok ( gk_dbuf_download . e kit pooled hp ) } {}
    ? ok {
        = bi 0
        ~ < bi take {
            : i t ( __em_vi ord + at bi )
            : ~ f ss 0.0
            : ~ i j 0
            ? normalize {
                ~ < j dim {
                    : f x ( __em_vf hp + * bi dim j )
                    = ss + ss * x x
                    = j + j 1
                }
            } {}
            : f nrm ( float_sqrt ss )
            : b div & normalize > nrm 0.0
            = j 0
            ~ < j dim {
                : f x ( __em_vf hp + * bi dim j )
                ( vec_set [f] out + * t dim j ? div { / x nrm } { x } )
                = j + j 1
            }
            = bi + bi 1
        }
    } {}
    ( vec_free [f] hp )
    ( gk_dbuf_free idb ) ( gk_dbuf_free mask ) ( gk_dbuf_free hid )
    ( gk_dbuf_free pooled ) ( gk_dbuf_free pw )
    ^ ok
}

// Embed B already-tokenized texts in one call. `ids` is flat token
// storage — text t occupies ids[offs[t] .. offs[t+1]), offs has B+1
// entries — and `out` must already hold B·dim floats; text t's vector is
// written in place at row t.
//
// Where the fused attention runs (CUDA, a supported head width), texts
// are sorted longest-first and packed greedily into chunks — a chunk's
// padded length is its LONGEST member's bucket, so the sort is what
// keeps short texts from being padded out to a long stranger's length —
// and each chunk is one batched forward (__em_fwd_batch). Everywhere
// else each text runs alone on the composed path, as it always has.
//
// The CUDA context is thread-local and this may be called from a
// server's worker rather than the thread that opened the model, so the
// device is bound to the caller first.
@ embed_encode_batch * Embed e ( Vec i ) ids ( Vec i ) offs ( Vec f ) out b normalize → b {
    ? . e ok {} { ^ F }
    ? ( gk_bind_thread . e kit ) {} { ^ F }
    : i nb - ( vec_len [i] offs ) 1
    ? > nb 0 {} { ^ F }
    : i dim . . e cfg dim
    ? >= ( vec_len [f] out ) * nb dim {} { ^ F }
    : ~ b ok T
    : ~ i t 0
    ~ < t nb {
        ? > ( __em_len offs t ) 0 {} { = ok F }
        = t + t 1
    }
    ? ok {} { ^ F }
    : i hd / dim . . e cfg heads
    ? ( gkd_attention_ok . e kit hd ) {} {
        = t 0
        ~ & ok < t nb {
            = ok ( __em_fwd_one e ids ( __em_vi offs t ) ( __em_len offs t ) out t normalize )
            = t + t 1
        }
        ^ ok
    }
    // longest first (insertion sort; a request batch is small)
    : ( Vec i ) ord ( vec_with_cap [i] nb )
    = t 0
    ~ < t nb { ( vec_push [i] ord t ) = t + t 1 }
    = t 1
    ~ < t nb {
        : i cur ( __em_vi ord t )
        : i cl ( __em_len offs cur )
        : ~ i j t
        : ~ b walk T
        ~ & walk > j 0 {
            ? < ( __em_len offs ( __em_vi ord - j 1 ) ) cl {
                ( vec_set [i] ord j ( __em_vi ord - j 1 ) )
                = j - j 1
            } { = walk F }
        }
        ( vec_set [i] ord j cur )
        = t + t 1
    }
    // greedy chunks under the row budget
    : i lim - - . . e cfg maxpos . . e cfg padid 1
    : ~ i at 0
    ~ & ok < at nb {
        : i l0 ( __em_len offs ( __em_vi ord at ) )
        : ~ i np ( __em_bucket l0 )
        ? > np lim { = np lim } {}
        ? >= np l0 {} { = ok F }
        ? ok {
            : ~ i take 1
            : ~ b grow T
            ~ & grow < + at take nb {
                // A chunk stays length-homogeneous: a text whose own
                // bucket is under half the chunk's np would spend more
                // than half its rows on padding — at 16 real tokens in a
                // 192-row slot that is 12x the arithmetic — and sorted
                // longest-first it (and everything after it) opens a
                // cheaper chunk of its own instead. Below 32 rows the
                // padding is launch-overhead noise, so tiny chunks merge
                // freely.
                : i cl ( __em_bucket ( __em_len offs ( __em_vi ord + at take ) ) )
                ? & & < take EM_BATCH_MAX <= * ( __em_bucket_b + take 1 ) np EM_ROWS_BUDGET
                | <= np 32 >= * cl 2 np {
                    = take + take 1
                } { = grow F }
            }
            : i bq ( __em_bucket_b take )
            = ok ( __em_fwd_batch e ids offs ord at take bq np normalize out )
            = at + at take
        } {}
    }
    ( vec_free [i] ord )
    ^ ok
}

// Forward over one already-tokenized id sequence — a batch of one.
@ embed_encode_ids_norm * Embed e ( Vec i ) ids ( Vec f ) out b normalize → b {
    ? . e ok {} { ^ F }
    : i dim . . e cfg dim
    ( vec_clear [f] out )
    : ~ i k 0
    ~ < k dim { ( vec_push [f] out 0.0 ) = k + k 1 }
    : ( Vec i ) offs ( vec_new [i] )
    ( vec_push [i] offs 0 )
    ( vec_push [i] offs ( vec_len [i] ids ) )
    : b r ( embed_encode_batch e ids offs out normalize )
    ( vec_free [i] offs )
    ^ r
}
