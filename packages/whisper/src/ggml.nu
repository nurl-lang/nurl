// packages/whisper/src/ggml.nu — whisper.cpp's LEGACY ggml container.
//
// The ggml-*.bin files ggerganov ships are how whisper models actually move
// between machines, and one is fully self-contained: hyperparameters, the
// tokenizer's vocabulary and every tensor in a single file — no config.json,
// no tokenizer.json. This reads that container so `whisper transcribe
// ggml-tiny.bin clip.wav` just works.
//
// It is a PARSER, not a runtime: the model still runs on this package's own
// kernels. (The original goal said "not ggml like whisper.cpp" — that was
// about the ggml LIBRARY; the file format is just bytes, and hostile-input
// rules apply: every length is checked against the mapping before use.)
//
// Layout (little-endian, no alignment padding):
//
//   u32 magic 'ggml'                          0x67676d6c
//   11 × i32 hparams                          n_vocab, n_audio_ctx,
//                                             n_audio_state, n_audio_head,
//                                             n_audio_layer, n_text_ctx,
//                                             n_text_state, n_text_head,
//                                             n_text_layer, n_mels, ftype
//   i32 n_mel, i32 n_fft, f32[n_mel*n_fft]    mel filters (unused here — ours
//                                             are verified against HF's)
//   i32 n_vocab_in_file, then per word:       i32 len, bytes (RAW bytes, not
//                                             the HF byte-encoding)
//   tensors until EOF:                        i32 n_dims, i32 name_len,
//                                             i32 ttype, i32 dims[n_dims],
//                                             name bytes, data
//
// Two translations happen at load so the REST of the pipeline stays exactly
// the HF pipeline:
//
//   * tensor names: whisper.cpp keeps OpenAI's names (encoder.blocks.0.attn.
//     query.weight); the model layer asks in HF names (model.encoder.layers.
//     0.self_attn.q_proj.weight). gg_find translates.
//   * the tokenizer: the file carries only the 50 257 base words, as raw
//     bytes. The special tokens have no text at all — whisper.cpp derives
//     their ids POSITIONALLY. We synthesize the HF spellings
//     (<|startoftranscript|>, <|fi|>, <|0.00|> …) at those positions and
//     byte-encode the base words, so name-based control-token lookup, the
//     timestamp rules and tok_decode work unchanged.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `deps/tokenizer/src/tokenizer.nu`
$ `deps/tokenizer/src/hf.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/mmap.nu`
$ `stdlib/core/slice.nu`

// dtype codes shared with the safetensor reader's ST_* so __wh_up's dispatch
// works on either source. ttype 0 = f32, 1 = f16; anything else is a
// quantised block format this package does not run yet.

// What the container says: the hyperparameters, the vocabulary and the
// tensor table — parsed once, never changed after.
: GgMeta {
    i n_vocab
    i n_audio_ctx
    i n_audio_state
    i n_audio_head
    i n_audio_layer
    i n_text_ctx
    i n_text_state
    i n_text_head
    i n_text_layer
    i n_mels
    ( Vec String ) vocab  // the raw base words, in id order
    ( Vec String ) tnames  // tensor names (ggml spelling)
    ( Vec i ) ttypes  // 0 = f32, 1 = f16
    ( Vec i ) tnelems
    ( Vec i ) toffs  // absolute byte offset of the tensor's data
}

// A Gg is a handle: every copy is the same container. The metadata is
// shared and frozen (an Arc); the file — an mmap where the platform has
// one (the page cache IS the copy, and a model that is already cached maps
// in with no I/O), the bytes read whole elsewhere — is a MappedFile the
// loader gives back once the weights are on the device: nothing reads the
// file after that, and 3 GB of a large model is not a thing to keep
// around for the vocabulary's sake. gg_close is an optional early release.
: Gg {
    ( Arc GgMeta ) meta
    ( Locked ? MappedFile ) file  // F once gg_release_data gave it back
}

@ Gg_share Gg h → Gg { ^ @ Gg { ( arc_clone [GgMeta] . h meta ) ( Locked_share [? MappedFile] . h file ) } }

@ Gg_drop sink Gg h → v {}

// The parsed container, lent.
@ gg_meta Gg h → GgMeta { ^ ( arc_get [GgMeta] . h meta ) }

// Give the file back — the mapping or the read buffer — and keep the
// parsed metadata (vocabulary, tensor table). gg_ptr answers null after.
@ gg_release_data Gg g → v { ( locked_set [? MappedFile] . g file @ ?MappedFile { F } ) }

// Early release (optional): the last owner gives everything back.
@ gg_close sink Gg g → v {}

// A little-endian i32 at `off`, sign and all.
@ __gg_i32 ( Slice u ) d i off → i {
    : ~ i v ( slice_u32_le d off )
    ? >= v 2147483648 { = v - v 4294967296 } {}
    ^ v
}

@ __gg_err s msg → !v String {
    ^ @ !v String { F ( string_from msg ) }
}

// Open a container: mapped for the one sweep the loader makes over it
// (file_map_stream: every page mapped in one pass, read ahead in order).
@ gg_open s path → !Gg String {
    ?? ( file_map_stream path ) {
        F _ → {
            : String m ( string_from `ggml: cannot read ` )
            ( string_push_str m path )
            ^ @ !Gg String { F m }
        }
        T mf → {
            : ~ GgMeta g @ GgMeta { 0 0 0 0 0 0 0 0 0 0 ( vec_new [String] ) ( vec_new [String] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) }
            ?? ( __gg_parse g ( mapped_bytes mf ) ) {
                T _ → { ^ @ !Gg String { T @ Gg { ( arc_new [GgMeta] g ) ( locked_new [? MappedFile] @ ?MappedFile { T mf } ) } } }
                F e → { ^ @ !Gg String { F e } }
            }
        }
    }
}

// The container's own parse over the mapped bytes: header, the mel filters
// (skipped), the vocabulary, the tensor table. Every length is checked
// against the mapping before it is trusted.
@ __gg_parse inout GgMeta g ( Slice u ) dd → !v String {
    : i n ( slice_len [u] dd )
    ? < n 56 {
        ^ ( __gg_err `ggml: file too short for a header` )
    } {}
    // magic 0x67676d6c on disk is the bytes 'l' 'm' 'g' 'g' —
    // checked as bytes, so nobody has to trust a decimal spelling
    ? | | | != ( slice_byte dd 0 ) 108 != ( slice_byte dd 1 ) 109 != ( slice_byte dd 2 ) 103 != ( slice_byte dd 3 ) 103 {
        ^ ( __gg_err `ggml: bad magic (not a ggml file)` )
    } {}
    = . g n_vocab ( __gg_i32 dd 4 )
    = . g n_audio_ctx ( __gg_i32 dd 8 )
    = . g n_audio_state ( __gg_i32 dd 12 )
    = . g n_audio_head ( __gg_i32 dd 16 )
    = . g n_audio_layer ( __gg_i32 dd 20 )
    = . g n_text_ctx ( __gg_i32 dd 24 )
    = . g n_text_state ( __gg_i32 dd 28 )
    = . g n_text_head ( __gg_i32 dd 32 )
    = . g n_text_layer ( __gg_i32 dd 36 )
    = . g n_mels ( __gg_i32 dd 40 )
    // hparams[10] = ftype; the per-tensor ttypes below are what
    // actually matter.

    // mel filters: skip (ours are verified against HF's own)
    : ~ i off 48
    ? > + off 8 n { ^ ( __gg_err `ggml: truncated at filters` ) } {}
    : i fmel ( __gg_i32 dd off )
    : i ffft ( __gg_i32 dd + off 4 )
    = off + off 8
    ? | | < fmel 0 < ffft 0 > + off * * fmel ffft 4 n {
        ^ ( __gg_err `ggml: filter block overruns the file` )
    } {}
    = off + off * * fmel ffft 4

    // vocabulary: raw words
    ? > + off 4 n { ^ ( __gg_err `ggml: truncated at vocab` ) } {}
    : i nvf ( __gg_i32 dd off )
    = off + off 4
    ? | < nvf 0 > nvf . g n_vocab {
        ^ ( __gg_err `ggml: vocab count is a lie` )
    } {}
    : ~ i k 0
    : ~ b vok T
    ~ & vok < k nvf {
        ? > + off 4 n { = vok F } {
            : i wl ( __gg_i32 dd off )
            = off + off 4
            ? | < wl 0 > + off wl n { = vok F } {
                : String w2 ( string_with_cap + wl 1 )
                : ~ i j 0
                ~ < j wl {
                    ( string_push_char w2 ( slice_byte dd + off j ) )
                    = j + j 1
                }
                ( vec_push [String] . g vocab w2 )
                = off + off wl
            }
        }
        = k + k 1
    }
    ? ! vok { ^ ( __gg_err `ggml: vocab overruns the file` ) } {}

    // tensors until EOF
    : ~ b tok2 T
    ~ & tok2 < off n {
        ? > + off 12 n { = tok2 F } {
            : i nd ( __gg_i32 dd off )
            : i nl ( __gg_i32 dd + off 4 )
            : i tt ( __gg_i32 dd + off 8 )
            = off + off 12
            ? | | | < nd 1 > nd 4 < nl 1 > nl 256 { = tok2 F } {
                ? > + off + * nd 4 nl n { = tok2 F } {
                    : ~ i ne 1
                    : ~ i di 0
                    ~ < di nd {
                        : i dv ( __gg_i32 dd + off * di 4 )
                        ? | < dv 1 > dv 16777216 { = tok2 F } {}
                        = ne * ne dv
                        = di + di 1
                    }
                    = off + off * nd 4
                    : String nm ( string_with_cap + nl 1 )
                    : ~ i nj 0
                    ~ < nj nl {
                        ( string_push_char nm ( slice_byte dd + off nj ) )
                        = nj + nj 1
                    }
                    = off + off nl
                    ? & != tt 0 != tt 1 {
                        ^ ( __gg_err `ggml: quantised tensors (q4/q5/q8) are not supported yet — use an f16 ggml model or the safetensors checkpoint` )
                    } {}
                    : i tsz * ne ? == tt 0 4 2
                    ? | ! tok2 > + off tsz n {
                        = tok2 F
                    } {
                        ( vec_push [String] . g tnames nm )
                        ( vec_push [i] . g ttypes tt )
                        ( vec_push [i] . g tnelems ne )
                        ( vec_push [i] . g toffs off )
                        = off + off tsz
                    }
                }
            }
        }
    }
    ? ! tok2 { ^ ( __gg_err `ggml: tensor block overruns the file` ) } {}
    ^ @ !v String { T 0 }
}

// ── HF name → ggml name ─────────────────────────────────────────────

@ __gg_suffix_map String out s suffix → v {
    ? != 0 ( nurl_str_eq suffix `self_attn.q_proj.weight` ) { ( string_push_str out `attn.query.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `self_attn.q_proj.bias` ) { ( string_push_str out `attn.query.bias` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `self_attn.k_proj.weight` ) { ( string_push_str out `attn.key.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `self_attn.v_proj.weight` ) { ( string_push_str out `attn.value.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `self_attn.v_proj.bias` ) { ( string_push_str out `attn.value.bias` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `self_attn.out_proj.weight` ) { ( string_push_str out `attn.out.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `self_attn.out_proj.bias` ) { ( string_push_str out `attn.out.bias` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `self_attn_layer_norm.weight` ) { ( string_push_str out `attn_ln.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `self_attn_layer_norm.bias` ) { ( string_push_str out `attn_ln.bias` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `encoder_attn.q_proj.weight` ) { ( string_push_str out `cross_attn.query.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `encoder_attn.q_proj.bias` ) { ( string_push_str out `cross_attn.query.bias` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `encoder_attn.k_proj.weight` ) { ( string_push_str out `cross_attn.key.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `encoder_attn.v_proj.weight` ) { ( string_push_str out `cross_attn.value.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `encoder_attn.v_proj.bias` ) { ( string_push_str out `cross_attn.value.bias` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `encoder_attn.out_proj.weight` ) { ( string_push_str out `cross_attn.out.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `encoder_attn.out_proj.bias` ) { ( string_push_str out `cross_attn.out.bias` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `encoder_attn_layer_norm.weight` ) { ( string_push_str out `cross_attn_ln.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `encoder_attn_layer_norm.bias` ) { ( string_push_str out `cross_attn_ln.bias` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `fc1.weight` ) { ( string_push_str out `mlp.0.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `fc1.bias` ) { ( string_push_str out `mlp.0.bias` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `fc2.weight` ) { ( string_push_str out `mlp.2.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `fc2.bias` ) { ( string_push_str out `mlp.2.bias` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `final_layer_norm.weight` ) { ( string_push_str out `mlp_ln.weight` ) ^ {} } {}
    ? != 0 ( nurl_str_eq suffix `final_layer_norm.bias` ) { ( string_push_str out `mlp_ln.bias` ) ^ {} } {}
    // unknown → keep as-is (the lookup will simply miss)
    ( string_push_str out suffix )
}

// Translate an HF tensor name to whisper.cpp's OpenAI spelling.
@ gg_map_name s hf → String {
    : String out ( string_new )
    ? != 0 ( nurl_str_eq hf `model.decoder.embed_tokens.weight` ) { ( string_push_str out `decoder.token_embedding.weight` ) ^ out } {}
    ? != 0 ( nurl_str_eq hf `model.decoder.embed_positions.weight` ) { ( string_push_str out `decoder.positional_embedding` ) ^ out } {}
    ? != 0 ( nurl_str_eq hf `model.encoder.embed_positions.weight` ) { ( string_push_str out `encoder.positional_embedding` ) ^ out } {}
    ? != 0 ( nurl_str_eq hf `model.encoder.layer_norm.weight` ) { ( string_push_str out `encoder.ln_post.weight` ) ^ out } {}
    ? != 0 ( nurl_str_eq hf `model.encoder.layer_norm.bias` ) { ( string_push_str out `encoder.ln_post.bias` ) ^ out } {}
    ? != 0 ( nurl_str_eq hf `model.decoder.layer_norm.weight` ) { ( string_push_str out `decoder.ln.weight` ) ^ out } {}
    ? != 0 ( nurl_str_eq hf `model.decoder.layer_norm.bias` ) { ( string_push_str out `decoder.ln.bias` ) ^ out } {}
    ? != 0 ( nurl_str_starts hf `model.encoder.conv` ) {
        // model.encoder.convN.{weight,bias} → encoder.convN.{weight,bias}
        ( string_push_str out ( nurl_str_slice hf 6 - ( nurl_str_len hf ) 6 ) )
        ^ out
    } {}
    // model.encoder.layers.<L>.<suffix> → encoder.blocks.<L>.<mapped>
    ? != 0 ( nurl_str_starts hf `model.encoder.layers.` ) {
        ( string_push_str out `encoder.blocks.` )
        : s rest ( nurl_str_slice hf 21 - ( nurl_str_len hf ) 21 )
        : ( Slice u ) rest_v ( slice_of_str rest )
        : i dot ( nurl_str_find rest `.` )
        ? < dot 0 { ( string_push_str out rest ) ^ out } {}
        : ~ i li 0
        ~ <= li dot { ( string_push_char out ( slice_byte rest_v li ) ) = li + li 1 }
        ( __gg_suffix_map out ( nurl_str_slice rest + dot 1 - ( nurl_str_len rest ) + dot 1 ) )
        ^ out
    } {}
    ? != 0 ( nurl_str_starts hf `model.decoder.layers.` ) {
        ( string_push_str out `decoder.blocks.` )
        : s rest ( nurl_str_slice hf 21 - ( nurl_str_len hf ) 21 )
        : ( Slice u ) rest_v ( slice_of_str rest )
        : i dot ( nurl_str_find rest `.` )
        ? < dot 0 { ( string_push_str out rest ) ^ out } {}
        : ~ i li 0
        ~ <= li dot { ( string_push_char out ( slice_byte rest_v li ) ) = li + li 1 }
        ( __gg_suffix_map out ( nurl_str_slice rest + dot 1 - ( nurl_str_len rest ) + dot 1 ) )
        ^ out
    } {}
    ( string_push_str out hf )
    ^ out
}

// Find a tensor by its HF name. -1 when absent.
@ gg_find Gg h s hf → i {
    : GgMeta g ( gg_meta h )
    : String gn ( gg_map_name hf )
    : ~ i found -1
    : ~ i k 0
    ~ & < k ( vec_len [String] . g tnames ) < found 0 {
        ?? ( vec_get [String] . g tnames k ) {
            T nm → {
                ? != 0 ( nurl_str_eq ( string_data nm ) ( string_data gn ) ) { = found k } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ found
}

@ gg_ttype Gg h i ti → i {
    : GgMeta g ( gg_meta h )
    ?? ( vec_get [i] . g ttypes ti ) { T x → { ^ x } F → { ^ -1 } }
}

@ gg_nelems Gg h i ti → i {
    : GgMeta g ( gg_meta h )
    ?? ( vec_get [i] . g tnelems ti ) { T x → { ^ x } F → { ^ 0 } }
}

// The address of tensor `ti`'s bytes in the file; null once the file was
// given back. raw: the caller keeps the file (any copy of `h`, before
// gg_release_data) while it reads there.
raw @ gg_ptr Gg h i ti → *u {
    : i o2 ?? ( vec_get [i] . ( gg_meta h ) toffs ti ) { T x → x F → 0 }
    : ?MappedFile f ( locked_take [? MappedFile] . h file )
    : ~ * u p # *u 0
    ?? f { T m → { = p # *u + # i ( mapped_ptr m ) o2 } F → {} }
    ( locked_restore [? MappedFile] . h file f )
    ^ p
}

// ── the tokenizer, synthesized ──────────────────────────────────────
//
// whisper.cpp's language table, in TOKEN ID ORDER — <|en|> is sot+1, <|zh|>
// sot+2, … This order is the model's, fixed at training time; large-v3
// appended yue as the 100th.
@ __gg_langs → s {
    ^ `en zh de es ru ko fr ja pt tr pl ca nl ar sv it id hi fi vi he uk el ms cs ro da hu ta no th ur hr bg lt la mi ml cy sk te fa lv bn sr az sl kn et mk br eu is hy ne mn bs kk sq sw gl mr pa si km sn yo so af oc ka be tg sd gu am yi lo uz fo ht ps tk nn mt sa lb my bo tl mg as tt haw ln ha ba jw su yue`
}

@ __gg_nth_word s list i idx → String {
    : ( Slice u ) list_v ( slice_of_str list )
    : String out ( string_new )
    : ~ i k 0
    : ~ i word 0
    : i n ( nurl_str_len list )
    ~ < k n {
        : i c ( slice_byte list_v k )
        ? == c 32 { = word + word 1 } {
            ? == word idx { ( string_push_char out c ) } {}
        }
        = k + k 1
    }
    ^ out
}

// Build the tokenizer: base words byte-encoded, specials synthesized at
// whisper.cpp's positional ids. Returns via tok_build so decode, control
// matching and the timestamp rules all behave exactly as with tokenizer.json.
@ gg_build_tok Gg h → !Tok String {
    : GgMeta g ( gg_meta h )
    : i nv . g n_vocab
    : i nfile ( vec_len [String] . g vocab )
    : b multi >= nv 51865
    : ~ i eot 50256
    : ~ i sot 50257
    ? multi { = eot + eot 1 = sot + sot 1 } {}
    : i nlang - - nv 51765 ? multi 1 0
    : i dt - nlang 98
    : i t_translate + 50357 dt
    : i t_transcribe + 50358 dt
    : i t_solm + 50359 dt
    : i t_prev + 50360 dt
    : i t_nosp + 50361 dt
    : i t_not + 50362 dt
    : i t_beg + 50363 dt

    : ( Vec String ) enc ( _tk_build_byte_enc )
    : ( Vec String ) pieces ( vec_new [String] )
    : ( Vec f ) scores ( vec_new [f] )
    : ( Vec i ) types ( vec_new [i] )
    : ( Vec String ) merges ( vec_new [String] )

    : ~ i id 0
    ~ < id nv {
        : String piece ( string_new )
        : ~ i ty TT_NORMAL
        ? < id nfile {
            // a base word: raw bytes → the HF byte-encoding, so tok_decode's
            // byte-decoder reproduces the original bytes exactly
            ?? ( vec_get [String] . g vocab id ) {
                T w2 → {
                    : ~ i bi 0
                    ~ < bi ( string_len w2 ) {
                        : i bv ( nurl_str_get ( string_data w2 ) bi )
                        ?? ( vec_get [String] enc bv ) {
                            T es → { ( string_push_str piece ( string_data es ) ) }
                            F → {}
                        }
                        = bi + bi 1
                    }
                }
                F → {}
            }
        } {
            // a synthesized special, at whisper.cpp's positional id
            = ty TT_CONTROL
            ? == id eot { ( string_push_str piece `<|endoftext|>` ) } {
                ? == id sot { ( string_push_str piece `<|startoftranscript|>` ) } {
                    ? & > id sot <= id + sot nlang {
                        : String lc ( __gg_nth_word ( __gg_langs ) - - id sot 1 )
                        ( string_push_str piece `<|` )
                        ( string_push_str piece ( string_data lc ) )
                        ( string_push_str piece `|>` )
                    } {
                        ? == id t_translate { ( string_push_str piece `<|translate|>` ) } {
                            ? == id t_transcribe { ( string_push_str piece `<|transcribe|>` ) } {
                                ? == id t_solm { ( string_push_str piece `<|startoflm|>` ) } {
                                    ? == id t_prev { ( string_push_str piece `<|startofprev|>` ) } {
                                        ? == id t_nosp { ( string_push_str piece `<|nospeech|>` ) } {
                                            ? == id t_not { ( string_push_str piece `<|notimestamps|>` ) } {
                                                ? >= id t_beg {
                                                    // <|0.00|> … <|30.00|>, one per 20 ms
                                                    : i cs2 * - id t_beg 2
                                                    ( string_push_str piece `<|` )
                                                    ( string_push_int piece / cs2 100 )
                                                    ( string_push_char piece 46 )
                                                    : i frac % cs2 100
                                                    ? < frac 10 { ( string_push_char piece 48 ) } {}
                                                    ( string_push_int piece frac )
                                                    ( string_push_str piece `|>` )
                                                } {
                                                    // a gap id whisper never emits — give it an unmatchable name
                                                    ( string_push_str piece `<|unused_` )
                                                    ( string_push_int piece id )
                                                    ( string_push_str piece `|>` )
                                                } } } } } } } } } }
        }
        ( vec_push [String] pieces piece )
        ( vec_push [f] scores 0.0 )
        ( vec_push [i] types ty )
        = id + id 1
    }
    : TokSpec spec @ TokSpec { TOK_BPE PRE_DEFAULT -1 eot -1 F F F }
    ^ ( tok_build spec pieces scores types merges )
}
