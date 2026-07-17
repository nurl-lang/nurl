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
//   ( embed_encode e text out )     → b     out = the embedding vector
//   ( embed_dim e ) ( embed_close e )
//
// Inference is per text (batch 1): no padding, no attention mask, and
// the numbers match sentence-transformers row for row. A batch endpoint
// loops — at embedding sizes the forward pass dominates regardless.
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
    // device
    = . e kit ( gk_open 0 )
    ? ( gk_ok . e kit ) {} { ( embed_close e ) ^ ( __em_err `embed: no compute device (CUDA or CPU backend)` ) }
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

// One transformer block over hidden[n,dim] (replaces `hid` content by
// writing into it at the residual+LN steps). Returns F on any failure.
@ __em_block * Embed e EmbedLayer l GkBuf hid i n → b {
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
    // heads: [n,heads,hd] → q,v: [heads,n,hd]; k: [heads,hd,n]
    : GkBuf qh ( __em_new e * n dim )
    : GkBuf kh ( __em_new e * n dim )
    : GkBuf vh ( __em_new e * n dim )
    : ( Vec i ) dims ( vec_new [i] )
    ( vec_push [i] dims n ) ( vec_push [i] dims heads ) ( vec_push [i] dims hd )
    : ( Vec i ) p102 ( vec_new [i] )
    ( vec_push [i] p102 1 ) ( vec_push [i] p102 0 ) ( vec_push [i] p102 2 )
    : ( Vec i ) p120 ( vec_new [i] )
    ( vec_push [i] p120 1 ) ( vec_push [i] p120 2 ) ( vec_push [i] p120 0 )
    ? ok { = ok ( gkd_perm . e kit qh q dims p102 ) } {}
    ? ok { = ok ( gkd_perm . e kit kh k dims p120 ) } {}
    ? ok { = ok ( gkd_perm . e kit vh v dims p102 ) } {}
    // scores[heads,n,n] = qh·kh / sqrt(hd)
    : GkBuf sc ( __em_new e * * heads n n )
    ? ok { = ok ( gkd_bmm . e kit sc qh kh heads n hd n 1 1 ) } {}
    : GkBuf scs ( __em_new e * * heads n n )
    : GkBuf inv ( __em_new e 1 )
    : ( Vec f ) hinv ( vec_new [f] )
    ( vec_push [f] hinv / 1.0 ( float_sqrt # f hd ) )
    ? ok { = ok ( gk_dbuf_upload . e kit inv hinv ) } {}
    ( vec_free [f] hinv )
    ? ok { = ok ( gkd_mul . e kit scs sc inv ) } {}
    // softmax over the last axis
    : GkBuf pr ( __em_new e * * heads n n )
    ? ok { = ok ( gkd_softmax_ax . e kit pr scs * heads n n 1 ) } {}
    // ctx[heads,n,hd] = pr·vh → merge back to [n,dim]
    : GkBuf ctx ( __em_new e * n dim )
    ? ok { = ok ( gkd_bmm . e kit ctx pr vh heads n n hd 1 1 ) } {}
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
    ( gk_dbuf_free sc ) ( gk_dbuf_free scs ) ( gk_dbuf_free inv )
    ( gk_dbuf_free pr ) ( gk_dbuf_free ctx ) ( gk_dbuf_free mrg )
    ( gk_dbuf_free ao ) ( gk_dbuf_free res )
    ( gk_dbuf_free h1 ) ( gk_dbuf_free h1g ) ( gk_dbuf_free h2 ) ( gk_dbuf_free res2 )
    ( vec_free [i] dims ) ( vec_free [i] dims2 )
    ( vec_free [i] p102 ) ( vec_free [i] p120 )
    ^ ok
}

// Tokenize (Unigram, <s>…</s>) with truncation to cfg.maxseq: the head
// of the sequence is kept and </s> re-appended, sentence-transformers
// style.
@ embed_tokenize * Embed e s text ( Vec i ) out → b {
    ? ( uni_encode . e tok text T out ) {} { ^ F }
    : i n ( vec_len [i] out )
    : i cap . . e cfg maxseq
    ? > n cap {
        : i eos ( uni_eos . e tok )
        : ~ b okt T
        ~ > ( vec_len [i] out ) - cap 1 { ?? ( vec_pop [i] out ) { T _ → {} F → { = okt F } } }
        ? & okt >= eos 0 { ( vec_push [i] out eos ) } {}
    } {}
    ^ T
}

// The embedding for one text. `out` receives embed_dim floats.
@ embed_encode * Embed e s text ( Vec f ) out → b {
    ? . e ok {} { ^ F }
    : ( Vec i ) ids ( vec_new [i] )
    ? ( embed_tokenize e text ids ) {} { ( vec_free [i] ids ) ^ F }
    : b r ( embed_encode_ids e ids out )
    ( vec_free [i] ids )
    ^ r
}

// Forward over an already-tokenized id sequence.
@ embed_encode_ids * Embed e ( Vec i ) ids ( Vec f ) out → b {
    ? . e ok {} { ^ F }
    : i n ( vec_len [i] ids )
    ? > n 0 {} { ^ F }
    : i dim . . e cfg dim
    : ~ b ok T
    // chain launches; one sync at the end of the walk
    ( gk_autosync F )
    // ids to the device
    : GkBuf idb ( gk_dbuf_new . e kit n GK_I64 )
    = ok ( gk_dbuf_upload_i . e kit idb ids )
    // hidden = word[ids] + positions[pad+1 .. pad+1+n) + type0
    : GkBuf hid ( __em_new e * n dim )
    ? ok { = ok ( gkd_gather . e kit hid . e wemb idb 1 . . e cfg vocab dim n ) } {}
    : GkBuf pos ( __em_new e * n dim )
    ? ok { = ok ( gkd_slice_ax . e kit pos . e pemb 1 n dim . . e cfg maxpos + . . e cfg padid 1 ) } {}
    : GkBuf sum1 ( __em_new e * n dim )
    ? ok { = ok ( gkd_add . e kit sum1 hid pos ) } {}
    // + token_type_embeddings[0] broadcast over rows
    : GkBuf sum2 ( __em_new e * n dim )
    : ( Vec i ) od ( vec_new [i] )
    ( vec_push [i] od n ) ( vec_push [i] od dim )
    : ( Vec i ) sa ( vec_new [i] )
    ( vec_push [i] sa dim ) ( vec_push [i] sa 1 )
    : ( Vec i ) sb ( vec_new [i] )
    ( vec_push [i] sb 0 ) ( vec_push [i] sb 1 )
    ? ok { = ok ( gkd_ew_bc . e kit `add` `+` sum2 sum1 . e temb od sa sb ) } {}
    ( vec_free [i] od ) ( vec_free [i] sa ) ( vec_free [i] sb )
    ? ok { = ok ( gkd_layernorm . e kit hid sum2 . e elnw . e elnb n dim . . e cfg eps ) } {}
    ( gk_dbuf_free pos ) ( gk_dbuf_free sum1 ) ( gk_dbuf_free sum2 )
    // blocks
    : i nl ( vec_len [EmbedLayer] . e layers )
    : ~ i l 0
    ~ & ok < l nl {
        ?? ( vec_get [EmbedLayer] . e layers l ) {
            T lay → { = ok ( __em_block e lay hid n ) }
            F → { = ok F }
        }
        = l + l 1
    }
    // pooling → a [1,dim] device vector
    : GkBuf pooled ( __em_new e dim )
    ? ok {
        ? == . . e cfg pool EM_POOL_MEAN {
            // mean over rows: ones[1,n]·hidden[n,dim] · (1/n)
            : GkBuf ones ( __em_new e n )
            : ( Vec f ) h1 ( vec_with_cap [f] n )
            : ~ i k 0
            ~ < k n { ( vec_push [f] h1 1.0 ) = k + k 1 }
            = ok ( gk_dbuf_upload . e kit ones h1 )
            ( vec_free [f] h1 )
            ? ok { = ok ( gkd_gemm . e kit pooled ones hid pooled 0 1 dim n / 1.0 # f n 0.0 0 ) } {}
            ( gk_dbuf_free ones )
        } {
            // CLS: row 0
            = ok ( gkd_slice_ax . e kit pooled hid 1 1 dim n 0 )
        }
    } {}
    ( gk_autosync T )
    // download + optional L2 normalize on the host
    ( vec_clear [f] out )
    : ~ i k2 0
    ~ < k2 dim { ( vec_push [f] out 0.0 ) = k2 + k2 1 }
    ? ok { = ok ( gk_dbuf_download . e kit pooled out ) } {}
    ? & ok . . e cfg normalize {
        : ~ f ss 0.0
        = k2 0
        ~ < k2 dim {
            ?? ( vec_get [f] out k2 ) { T x → { = ss + ss * x x } F → {} }
            = k2 + k2 1
        }
        : f nrm ( float_sqrt ss )
        ? > nrm 0.0 {
            = k2 0
            ~ < k2 dim {
                ?? ( vec_get [f] out k2 ) { T x → { ( vec_set [f] out k2 / x nrm ) } F → {} }
                = k2 + k2 1
            }
        } {}
    } {}
    ( gk_dbuf_free idb ) ( gk_dbuf_free hid ) ( gk_dbuf_free pooled )
    ^ ok
}
