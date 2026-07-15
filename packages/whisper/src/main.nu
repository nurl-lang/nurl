// packages/whisper/src/main.nu — the CLI (encoder stage).
//
//   whisper transcribe <model-dir> <audio.wav> [--lang en] [--max N]
//   whisper encode     <config.json> <model.safetensors> <audio.wav> -o enc.f32
//
// `transcribe` is the whole thing: WAV → log-mel → encoder → decoder → text.
// `encode` stops after the encoder and writes its 1500 × d_model states, which
// is what the test suite compares against HF's WhisperModel.encoder.
//
// A model directory is what Hugging Face ships: config.json, model.safetensors
// and tokenizer.json, side by side.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/audio/src/wav.nu`
$ `deps/audio/src/mel.nu`
$ `deps/audio/src/resample.nu`
$ `deps/audio/src/vad.nu`
$ `deps/tokenizer/src/tokenizer.nu`
$ `deps/tokenizer/src/hf.nu`
$ `src/ggml.nu`
$ `src/model.nu`
$ `src/serve.nu`

@ __wcli_write_f32 s path ( Vec f ) v → i {
    : ( Vec u ) d ( vec_with_cap [u] * 4 ( vec_len [f] v ) )
    : ~ i k 0
    ~ < k ( vec_len [f] v ) {
        ?? ( vec_get [f] v k ) {
            T x → { ( bytes_push_u32_le d # u32 ( f32_to_bits # f32 x ) ) }
            F → {}
        }
        = k + k 1
    }
    : ~ i rc 0
    ?? ( write_file_bytes path d ) {
        T _ → {}
        F _ → {
            ( nurl_eprintln `whisper: cannot write output` )
            = rc 1
        }
    }
    ( vec_free [u] d )
    ^ rc
}

// Is `model` a whisper.cpp ggml container? Decided by the file's own first
// bytes ('lmgg' on disk), not the extension — a renamed file still works and
// a directory never opens as a file.
@ __wh_is_ggml s model → b {
    ?? ( file_open model ) {
        T f → {
            : ~ b yes F
            ?? ( file_read_at f 0 4 ) {
                T h → {
                    ? == ( vec_len [u] h ) 4 {
                        : ~ i b0 0
                        : ~ i b1 0
                        : ~ i b2 0
                        : ~ i b3 0
                        ?? ( vec_get [u] h 0 ) { T x0 → { = b0 # i x0 } F → {} }
                        ?? ( vec_get [u] h 1 ) { T x1 → { = b1 # i x1 } F → {} }
                        ?? ( vec_get [u] h 2 ) { T x2 → { = b2 # i x2 } F → {} }
                        ?? ( vec_get [u] h 3 ) { T x3 → { = b3 # i x3 } F → {} }
                        = yes & & & == b0 108 == b1 109 == b2 103 == b3 103
                    } {}
                    ( vec_free [u] h )
                }
                F _ → {}
            }
            ( file_close f )
            ^ yes
        }
        F _ → { ^ F }
    }
}

// <dir>/<name>
@ _wh_path s dir s name → String {
    : String p2 ( string_from dir )
    ? > ( string_len p2 ) 0 {
        ? != ( nurl_str_get ( string_data p2 ) - ( string_len p2 ) 1 ) 47 {
            ( string_push_char p2 47 )
        } {}
    } {}
    ( string_push_str p2 name )
    ^ p2
}

// A whisper prompt is four control tokens, and getting them wrong is not a
// subtle failure: the model is being told what task it is doing.
//
//   <|startoftranscript|> <|LANG|> <|transcribe|> <|notimestamps|>
//
// Their ids are NOT hardcoded here — they are looked up in the vocabulary the
// checkpoint ships, because they move between whisper versions (v3 added a
// language and every id after it shifted).
@ __wh_special * Tok t s name → i {
    : ( Vec i ) ids ( tok_encode t name T )
    : ~ i id -1
    ? == 1 ( vec_len [i] ids ) {
        ?? ( vec_get [i] ids 0 ) { T x → { = id x } F → {} }
    } {}
    ( vec_free [i] ids )
    ^ id
}

// mm:ss.cc — enough resolution for whisper's own 20 ms grid.
@ __wh_fmt_time String out f secs → v {
    : ~ f t2 secs
    ? < t2 0.0 { = t2 0.0 } {}
    : i cs # i + * t2 100.0 0.5
    : i mn / cs 6000
    : i sec / % cs 6000 100
    : i frac % cs 100
    ? < mn 10 { ( string_push_char out 48 ) } {}
    ( string_push_int out mn )
    ( string_push_char out 58 )
    ? < sec 10 { ( string_push_char out 48 ) } {}
    ( string_push_int out sec )
    ( string_push_char out 46 )
    ? < frac 10 { ( string_push_char out 48 ) } {}
    ( string_push_int out frac )
}

// A timestamp in the timeline the model SAW, mapped to the recording the caller
// HAS. They differ twice over: the window offset is added by the caller before
// this (the model's clock restarts at zero every 30-second window), and --vad
// removed the silence — so second 12 of the condensed audio may be minute 3 of
// the recording. The VadRun map is what walks that back.
@ __wh_map_time ( Vec VadRun ) runs f t → f {
    ? == ( vec_len [VadRun] runs ) 0 { ^ t } {}
    ^ / # f ( vad_map_sample runs # i * t 16000.0 ) 16000.0
}

// One "[a --> b] text" line from a slice of the decoded ids.
@ __wh_emit_seg * Tok t ( Vec i ) ids i from i to ( Vec VadRun ) runs f t0 f t1 ( Vec u ) out → v {
    ? <= to from { ^ {} } {}
    : ( Vec i ) seg ( vec_new [i] )
    : ~ i k from
    ~ < k to {
        ?? ( vec_get [i] ids k ) { T x → { ( vec_push [i] seg x ) } F → {} }
        = k + k 1
    }
    : ( Vec u ) txt ( tok_decode t seg )
    : String line ( string_from `[` )
    ( __wh_fmt_time line ( __wh_map_time runs t0 ) )
    ( string_push_str line ` --> ` )
    ( __wh_fmt_time line ( __wh_map_time runs t1 ) )
    ( string_push_str line `]` )
    : ~ i j 0
    ~ < j ( string_len line ) {
        ( vec_push [u] out ( nurl_str_get ( string_data line ) j ) )
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [u] txt ) {
        ?? ( vec_get [u] txt j ) { T b → { ( vec_push [u] out b ) } F → {} }
        = j + j 1
    }
    ( vec_push [u] out 10 )
    ( string_free line )
    ( vec_free [u] txt )
    ( vec_free [i] seg )
}

// Timestamp decoding is not "leave <|notimestamps|> out and hope": whisper was
// TRAINED under constraints, and greedy decoding without them almost never
// emits a timestamp — the text token is always individually likelier than any
// single one of 1500 timestamp bins. These are openai's own rules:
//
//   * the first generated token is a timestamp (capped at <|1.00|> — speech
//     rarely starts later than that in a window that VAD or a human queued up)
//   * timestamps never go backwards
//   * they come in pairs: a timestamp that CLOSES text is followed by the one
//     that opens the next segment (or by <|endoftext|>); two in a row are
//     followed by text
//   * and the one that makes it work at all: the timestamp bins are compared
//     against the best text token COLLECTIVELY — if their summed probability
//     beats it, the next token is a timestamp, even though no single bin wins.
//     One second of speech spreads its boundary over dozens of 20 ms bins, and
//     asking any single bin to out-score "the" is asking the wrong question.
@ __wh_next_ts ( Vec f ) lg i ts0 i eot b first b last_ts b penult_ts i min_id → i {
    : i n ( vec_len [f] lg )
    // best text token (everything below ts0), best ts token ≥ min_id, and
    // logsumexp over that same ts range — one pass
    : ~ i bt -1
    : ~ f btv -1.0e30
    : ~ i bts -1
    : ~ f btsv -1.0e30
    : ~ f mx -1.0e30
    : ~ i lo ? > min_id ts0 min_id ts0
    : ~ i hi n
    ? first {
        = lo ts0
        = hi + ts0 51
        ? > hi n { = hi n } {}
    } {}
    : ~ i k 0
    ~ < k ts0 {
        : f v0 ?? ( vec_get [f] lg k ) { T x → x F → -1.0e30 }
        ? > v0 btv { = btv v0 = bt k } {}
        = k + k 1
    }
    = k lo
    ~ < k hi {
        : f v1 ?? ( vec_get [f] lg k ) { T x → x F → -1.0e30 }
        ? > v1 btsv { = btsv v1 = bts k } {}
        ? > v1 mx { = mx v1 } {}
        = k + k 1
    }
    ? < bts 0 { ^ bt } {}
    ? first { ^ bts } {}
    // after text + one timestamp: the pair's second half, or the end
    ? & last_ts ! penult_ts {
        : f ev ?? ( vec_get [f] lg eot ) { T x → x F → -1.0e30 }
        ^ ? > ev btsv eot bts
    } {}
    // two timestamps in a row: text next
    ? & last_ts penult_ts { ^ bt } {}
    // open segment: text competes against the timestamp bins COLLECTIVELY
    : ~ f lse 0.0
    = k lo
    ~ < k hi {
        : f v2 ?? ( vec_get [f] lg k ) { T x → x F → -1.0e30 }
        = lse + lse ( exp - v2 mx )
        = k + k 1
    }
    : f tsmass + mx ( log lse )
    ? > tsmass btv { ^ bts } {}
    ^ ? > btv btsv bt bts
}

// Decode ONE 30-second window: the encoder has already run over it, and the
// cross-attention K/V are prepared. Appends the text to `out` — plain, or as
// "[a --> b] text" lines when `with_ts` is set.
//
// The timestamps are the model's own: with <|notimestamps|> left OUT of the
// prompt, whisper interleaves timestamp tokens (<|0.00|> … <|30.00|>, one per
// 20 ms) with the words — it was trained to. `win_off` places this window in
// the condensed timeline; `runs` places the condensed timeline in the
// recording.
@ __wh_decode_window * Whisper w * Tok t s lang i maxtok b with_ts f win_off ( Vec VadRun ) runs ( Vec u ) out → b {
    : String ltok ( string_from `<|` )
    ( string_push_str ltok lang )
    ( string_push_str ltok `|>` )
    : i sot ( __wh_special t `<|startoftranscript|>` )
    : i lid ( __wh_special t ( string_data ltok ) )
    : i task ( __wh_special t `<|transcribe|>` )
    : i nots ( __wh_special t `<|notimestamps|>` )
    : i eot ( __wh_special t `<|endoftext|>` )
    ( string_free ltok )
    ? | | | | < sot 0 < lid 0 < task 0 < nots 0 < eot 0 { ^ F } {}

    : ( Vec i ) prompt ( vec_new [i] )
    // <|0.00|> is looked up like every other control token; openai's own code
    // hardcodes timestamp_begin = notimestamps+1, which is the fallback if a
    // vocabulary does not list the timestamp tokens outright.
    : ~ i ts0 ( __wh_special t `<|0.00|>` )
    ? < ts0 0 { = ts0 + nots 1 } {}
    ( vec_push [i] prompt sot )
    ( vec_push [i] prompt lid )
    ( vec_push [i] prompt task )
    ? with_ts {} { ( vec_push [i] prompt nots ) }
    : ( Vec i ) outids ( vec_new [i] )
    : ~ i pos 0
    : ~ i k 0
    ~ < k ( vec_len [i] prompt ) {
        ?? ( vec_get [i] prompt k ) {
            T tk → { ( wh_decode_step w tk pos ) }
            F → {}
        }
        = pos + pos 1
        = k + k 1
    }
    : ~ b done F
    : ~ i made 0
    : ~ i last -1
    : ~ i last2 -1
    : ~ i mints ts0
    ~ & ! done < made maxtok {
        : ( Vec f ) lg ( wh_logits w )
        : ~ i nt 0
        ? with_ts {
            // openai's exact framing: with FEWER than two sampled tokens the
            // penultimate counts as a timestamp — getting this edge wrong makes
            // the "pair or end" rule fire right after the opening <|0.00|> and
            // the decode ends at one token.
            : b lts & >= made 1 >= last ts0
            : b pts | < made 2 >= last2 ts0
            = nt ( __wh_next_ts lg ts0 eot == made 0 lts pts mints )
        } {
            = nt ( wh_argmax lg )
        }
        ( vec_free [f] lg )
        ? == nt eot { = done T } {
            = last2 last
            = last nt
            ? >= nt ts0 { = mints nt } {}
            ( vec_push [i] outids nt )
            ( wh_decode_step w nt pos )
            = pos + pos 1
            = made + made 1
        }
    }
    ? with_ts {
        // ids → segments. A timestamp token closes the text gathered since the
        // previous one (whisper emits them in pairs — <|a|> words <|b|> — and a
        // bare pair boundary is just two in a row, which leaves no text and
        // emits nothing).
        : i nids ( vec_len [i] outids )
        : ~ f cur win_off
        : ~ i segfrom 0
        : ~ i j 0
        ~ < j nids {
            : ~ i id -1
            ?? ( vec_get [i] outids j ) { T x → { = id x } F → {} }
            ? & >= id ts0 <= id + ts0 1500 {
                : f tt + win_off * 0.02 # f - id ts0
                ( __wh_emit_seg t outids segfrom j runs cur tt out )
                = cur tt
                = segfrom + j 1
            } {}
            = j + j 1
        }
        ( __wh_emit_seg t outids segfrom nids runs cur + win_off 30.0 out )
    } {
        : ( Vec u ) txt ( tok_decode t outids )
        : ~ i j 0
        ~ < j ( vec_len [u] txt ) {
            ?? ( vec_get [u] txt j ) {
                T b → { ( vec_push [u] out b ) }
                F → {}
            }
            = j + j 1
        }
        ( vec_free [u] txt )
    }
    ( vec_free [i] outids )
    ( vec_free [i] prompt )
    ^ T
}

// Audio longer than 30 seconds is transcribed in 30-second WINDOWS: the encoder
// sees exactly 30 s (that is the length it was trained on and the length its
// positional embedding has), so a longer clip is split, and each window is
// decoded from a fresh prompt with its own KV cache.
// The transcription core, from samples to text: VAD (optional), the 30-second
// window loop, decode. TAKES OWNERSHIP of `at16_in` (16 kHz mono) — the VAD
// path replaces the buffer wholesale, so the caller's handle is dead either
// way, and this function frees whichever buffer survives.
//
// This is the seam the server stands on: the CLI opens the model, runs this
// once and exits; `whisper serve` opens the model ONCE and runs this per
// request — the 1.5 GB read, the f16→f32 conversion and the kernel compile
// all happen before the first request instead of inside every one.
@ wh_run * Whisper w * Tok t ( Vec f ) at16_in s lang i maxtok b use_vad b with_ts ( Vec u ) out → b {
    : ~ ( Vec f ) at16 at16_in
    // where each surviving stretch of condensed audio sits in the
    // recording — empty (identity) without VAD
    : ( Vec VadRun ) runs ( vec_new [VadRun] )
    ? use_vad {
        : ( Vec VadSeg ) segs ( vad_segments at16 16000 ( vad_default_opts ) )
        // 0.5 s of the real room is kept between segments — enough of a
        // boundary that two sentences do not run together, far less than
        // the pause it replaces.
        : ( Vec f ) sp ( vad_extract_runs at16 segs 8000 runs )
        ( vec_free [f] at16 )
        = at16 sp
        ( vec_free [VadSeg] segs )
    } {}
    : i nmel . w n_mels
    : i total ( vec_len [f] at16 )
    // the window is the encoder's own length: 1500 positions × 2 (the
    // stride-2 conv) × 160 samples of hop = 30 s at 16 kHz. Derived, not
    // assumed.
    : i window * . w n_ctx_enc 320
    // no audio (or, under VAD, no speech in it) is no windows — not one
    // window of silence. Whisper asked to transcribe silence does not
    // return nothing; it returns "[BLANK_AUDIO]", or a sentence it made up.
    : i nwin ? > total 0 / + total - window 1 window 0
    : ~ b ok T
    : ~ i wi 0
    ~ & ok < wi nwin {
        : i from * wi window
        : ( Vec f ) chunk ( vec_new [f] )
        : ~ i k 0
        ~ & < k window < + from k total {
            ?? ( vec_get [f] at16 + from k ) {
                T x → { ( vec_push [f] chunk x ) }
                F → {}
            }
            = k + k 1
        }
        : ( Vec f ) fixed ( pad_or_trim chunk window )
        : ( Vec f ) mel ( log_mel_whisper fixed 400 160 nmel 16000 )
        ( vec_free [f] chunk )
        ( vec_free [f] fixed )
        ( wh_encode w mel )
        ( wh_prepare_cross w )
        ( vec_free [f] mel )
        : f woff / # f * wi window 16000.0
        ? ( __wh_decode_window w t lang maxtok with_ts woff runs out ) {} { = ok F }
        = wi + wi 1
    }
    ( vec_free [f] at16 )
    ( vec_free [VadRun] runs )
    ^ ok
}

// The shared tail once the model and tokenizer are open: read the audio,
// resample, run, print. Owns neither w nor t.
@ __wh_transcribe_run * Whisper w * Tok t s wavpath s lang i maxtok b use_vad b with_ts → i {
    : ~ i rc 0
    ?? ( wav_read wavpath ) {
        T aw → {
            : ( Vec f ) mono ( wav_mono aw )
            : ( Vec f ) at16 ( resample mono . aw rate 16000 )
            ( wav_free aw )
            ( vec_free [f] mono )
            : ( Vec u ) text ( vec_new [u] )
            ? ( wh_run w t at16 lang maxtok use_vad with_ts text ) {
                : i n ( vec_len [u] text )
                ? > n 0 { : i _w ( write 1 # *u ( vec_data [u] text ) n ) } {}
                ( nurl_print `\n` )
            } {
                ( nurl_eprintln `whisper: the vocabulary has no control tokens (is this a whisper model?)` )
                = rc 1
            }
            ( vec_free [u] text )
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            = rc 1
        }
    }
    ^ rc
}

@ __wh_transcribe s dir s wavpath s lang i maxtok b use_vad b with_ts → i {
    // whisper.cpp's ggml container: hyperparameters, tokenizer and weights in
    // ONE file — no config.json or tokenizer.json beside it
    ? ( __wh_is_ggml dir ) {
        ?? ( wh_open_ggml dir ) {
            T w → {
                : ~ i rc2 1
                ?? ( gg_build_tok # *Gg . w gg ) {
                    T t → {
                        = rc2 ( __wh_transcribe_run w t wavpath lang maxtok use_vad with_ts )
                        ( tok_free t )
                    }
                    F e → {
                        ( nurl_eprintln ( string_data e ) )
                        ( string_free e )
                    }
                }
                ( wh_close w )
                ^ rc2
            }
            F e → {
                ( nurl_eprintln ( string_data e ) )
                ( string_free e )
                ^ 1
            }
        }
    } {}
    : String cfg ( _wh_path dir `config.json` )
    : String wts ( _wh_path dir `model.safetensors` )
    : String tjs ( _wh_path dir `tokenizer.json` )

    : TokSpec spec @ TokSpec { TOK_BPE PRE_DEFAULT -1 -1 -1 F F F }
    : ~ i rc 0
    ?? ( tok_from_tokenizer_json ( string_data tjs ) spec ) {
        T t → {
            ?? ( wav_read wavpath ) {
                T aw → {
                    : ( Vec f ) mono ( wav_mono aw )
                    : ( Vec f ) at16 ( resample mono . aw rate 16000 )
                    ( wav_free aw )
                    ( vec_free [f] mono )
                    // The model is opened BEFORE the spectrogram is computed:
                    // how many mel bands it wants is a property of the model
                    // (80 for whisper-tiny … large-v2, 128 for large-v3 and
                    // distil-large-v3), and a hardcoded 80 would feed the
                    // large-v3 encoder a spectrogram of the wrong shape.
                    ?? ( wh_open ( string_data cfg ) ( string_data wts ) ) {
                        T w → {
                            : ( Vec u ) text ( vec_new [u] )
                            ? ( wh_run w t at16 lang maxtok use_vad with_ts text ) {
                                : i n ( vec_len [u] text )
                                ? > n 0 { : i _w ( write 1 # *u ( vec_data [u] text ) n ) } {}
                                ( nurl_print `\n` )
                            } {
                                ( nurl_eprintln `whisper: the vocabulary has no control tokens (is this a whisper tokenizer.json?)` )
                                = rc 1
                            }
                            ( vec_free [u] text )
                            ( wh_close w )
                        }
                        F e → {
                            ( nurl_eprintln ( string_data e ) )
                            ( string_free e )
                            = rc 1
                        }
                    }
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                    ( string_free e )
                    = rc 1
                }
            }
            ( tok_free t )
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            = rc 1
        }
    }
    ( string_free cfg ) ( string_free wts ) ( string_free tjs )
    ^ rc
}

@ main → i {
    : ArgParser p ( args_new `whisper` `Speech recognition in pure NURL (encoder stage).` )
    ( args_opt p `output` 111 `FILE` `write the encoder states here (f32 LE)` )
    ( args_opt p `lang` 0 `LANG` `transcribe/serve: the language token (default en)` )
    ( args_opt p `addr` 0 `HOST:PORT` `serve: listen here (default 127.0.0.1:6543)` )
    ( args_opt p `max` 0 `N` `transcribe: stop after N tokens (default 200)` )
    ( args_flag p `vad` 0 `transcribe: skip the silence (energy VAD) before the model sees it` )
    ( args_flag p `timestamps` 0 `transcribe: "[a --> b] text" segments, in the RECORDING's timeline` )
    ( args_flag p `help` 104 `show this help` )
    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  encode <config.json> <model.safetensors> <audio.wav> -o enc.f32\n` )
        ( string_free u )
        ( args_free p )
        ^ 0
    } {}
    ? < ( args_positional_count p ) 2 {
        ( nurl_eprintln `usage: whisper transcribe <model-dir> <audio.wav> · whisper serve <model-dir> --addr host:port · whisper encode <config.json> <model.safetensors> <audio.wav> -o enc.f32` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd0 ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmd0 ( string_data c ) } F → {} }
    ? ( nurl_str_eq cmd0 `serve` ) {
        : ~ s dir ``
        ?? ( vec_get [String] pos 1 ) { T c → { = dir ( string_data c ) } F → {} }
        : String lang ( args_value_or p `lang` `en` )
        : ~ i maxtok 200
        : String smax ( args_value_or p `max` `200` )
        ?? ( string_to_int smax ) { T v → { = maxtok v } F _ → {} }
        ( string_free smax )
        // --addr host:port — the LAST colon splits, so a future [::1]:port
        // does not shear an IPv6 address in half
        : String addr ( args_value_or p `addr` `127.0.0.1:6543` )
        : ~ i colon -1
        : ~ i ai 0
        ~ < ai ( string_len addr ) {
            ? == 58 ( nurl_str_get ( string_data addr ) ai ) { = colon ai } {}
            = ai + ai 1
        }
        : ~ i port 6543
        : String host ( string_new )
        ? >= colon 0 {
            = ai 0
            ~ < ai colon {
                ( string_push_char host ( nurl_str_get ( string_data addr ) ai ) )
                = ai + ai 1
            }
            : String ps ( string_new )
            = ai + colon 1
            ~ < ai ( string_len addr ) {
                ( string_push_char ps ( nurl_str_get ( string_data addr ) ai ) )
                = ai + ai 1
            }
            ?? ( string_to_int ps ) { T v → { = port v } F _ → {} }
            ( string_free ps )
        } {
            ( string_push_str host ( string_data addr ) )
        }
        : i rc ( wh_serve dir ( string_data host ) port ( string_data lang ) maxtok ( args_present p `vad` ) ( args_present p `timestamps` ) )
        ( string_free host )
        ( string_free addr )
        ( string_free lang )
        ( args_free p )
        ^ rc
    } {}
    ? < ( args_positional_count p ) 3 {
        ( nurl_eprintln `usage: whisper transcribe <model-dir> <audio.wav> · whisper serve <model-dir> --addr host:port · whisper encode <config.json> <model.safetensors> <audio.wav> -o enc.f32` )
        ( args_free p )
        ^ 2
    } {}
    ? ( nurl_str_eq cmd0 `transcribe` ) {
        : ~ s dir ``
        : ~ s awav ``
        ?? ( vec_get [String] pos 1 ) { T c → { = dir ( string_data c ) } F → {} }
        ?? ( vec_get [String] pos 2 ) { T c → { = awav ( string_data c ) } F → {} }
        : String lang ( args_value_or p `lang` `en` )
        : ~ i maxtok 200
        : String smax ( args_value_or p `max` `200` )
        ?? ( string_to_int smax ) { T v → { = maxtok v } F _ → {} }
        ( string_free smax )
        : i rc ( __wh_transcribe dir awav ( string_data lang ) maxtok ( args_present p `vad` ) ( args_present p `timestamps` ) )
        ( string_free lang )
        ( args_free p )
        ^ rc
    } {}
    : ~ s cfg ``
    : ~ s wts ``
    : ~ s wav ``
    ?? ( vec_get [String] pos 1 ) { T c → { = cfg ( string_data c ) } F → {} }
    ?? ( vec_get [String] pos 2 ) { T c → { = wts ( string_data c ) } F → {} }
    ?? ( vec_get [String] pos 3 ) { T c → { = wav ( string_data c ) } F → {} }

    ?? ( wav_read wav ) {
        T aw → {
            : ( Vec f ) mono ( wav_mono aw )
            : ( Vec f ) at16 ( resample mono . aw rate 16000 )
            ( wav_free aw )
            ( vec_free [f] mono )
            // at16 is NOT freed here: the model has to be opened first (how many
            // mel bands it wants and how long a window it sees are ITS
            // properties), and pad_or_trim reads at16 after that. Freeing it
            // early was a use-after-free that whisper-tiny survived by luck —
            // the freed pages were still intact — and distil-large-v3 turned
            // into a segfault. A Vec is a shared boxed handle; free it once, at
            // the end, on every path.
            ?? ( wh_open cfg wts ) {
                T w → {
                    : ( Vec f ) fixed ( pad_or_trim at16 * . w n_ctx_enc 320 )
                    : ( Vec f ) mel ( log_mel_whisper fixed 400 160 . w n_mels 16000 )
                    ( vec_free [f] fixed )
                    ( vec_free [f] at16 )
                    ( wh_encode w mel )
                    : ( Vec f ) enc ( wh_enc_out w )
                    : String o ( args_value_or p `output` `enc.f32` )
                    : i rc ( __wcli_write_f32 ( string_data o ) enc )
                    : String m ( string_from `encoder — ` )
                    ( string_push_int m . w n_ctx_enc )
                    ( string_push_str m ` x ` )
                    ( string_push_int m . w d_model )
                    ( string_push_str m ` states → ` )
                    ( string_push_str m ( string_data o ) )
                    ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
                    ( string_free m )
                    ( string_free o )
                    ( vec_free [f] enc )
                    ( vec_free [f] mel )
                    ( wh_close w )
                    ( args_free p )
                    ^ rc
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                    ( string_free e )
                    ( vec_free [f] at16 )
                    ( args_free p )
                    ^ 1
                }
            }
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ( args_free p )
            ^ 1
        }
    }
}
