// packages/whisper/src/run.nu — the shared middle of the pipeline: what
// `transcribe` and `serve` both do once a model and a tokenizer are open.
//
//   _wh_is_ggml / _wh_path   which container a model argument names
//   wh_run                   16 kHz mono float samples → the words (with
//                            --vad's condensed timeline mapped back, and
//                            whisper's own timestamp tokens when asked)
//
// The CLI (main.nu) and the server (serve.nu) import this rather than each
// other: every source module compiles on its own, which is what the
// publish gate checks.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
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

// Is `model` a whisper.cpp ggml container? Decided by the file's own first
// bytes ('lmgg' on disk), not the extension — a renamed file still works and
// a directory never opens as a file.
@ _wh_is_ggml s model → b {
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

// p(<|nospeech|>) from a logits vector — softmax'd on the host, one pass
// for the max, one for the sum. ~50k exps is microseconds next to the
// forward pass that produced the logits.
@ __wh_nosp_prob ( Vec f ) lg i nosp → f {
    : i n ( vec_len [f] lg )
    : ~ f mx -1.0e30
    : ~ i k 0
    ~ < k n {
        : ~ f v 0.0
        ?? ( vec_get [f] lg k ) { T x → { = v x } F → {} }
        ? > v mx { = mx v } {}
        = k + k 1
    }
    : ~ f se 0.0
    = k 0
    ~ < k n {
        : ~ f v2 0.0
        ?? ( vec_get [f] lg k ) { T x2 → { = v2 x2 } F → {} }
        = se + se ( exp - v2 mx )
        = k + k 1
    }
    : ~ f ln 0.0
    ?? ( vec_get [f] lg nosp ) { T xn → { = ln xn } F → {} }
    ^ / ( exp - ln mx ) se
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
@ __wh_decode_window * Whisper w * Tok t s lang i maxtok b with_ts f win_off ( Vec VadRun ) runs f nospeech ( Vec u ) out → b {
    // Language codes are lowercase by definition (<|fi|>, <|en|> …) — a
    // phone keyboard capitalizes the first letter, and "Fi" failing with
    // no explanation is a bug report waiting to happen. Normalize here,
    // at the one place the token text is built.
    : String ltok ( string_from `<|` )
    : ~ i lci 0
    ~ < lci ( nurl_str_len lang ) {
        : ~ i lc ( nurl_str_get lang lci )
        ? & >= lc 65 <= lc 90 { = lc + lc 32 } {}
        ( string_push_char ltok lc )
        = lci + lci 1
    }
    ( string_push_str ltok `|>` )
    : i sot ( __wh_special t `<|startoftranscript|>` )
    : i lid ( __wh_special t ( string_data ltok ) )
    : i task ( __wh_special t `<|transcribe|>` )
    : i nots ( __wh_special t `<|notimestamps|>` )
    : i eot ( __wh_special t `<|endoftext|>` )
    // large-v3-era vocabularies spell it <|nospeech|>; the earlier ones
    // (tiny…large-v2 as Hugging Face ships them) say <|nocaptions|> for the
    // SAME positional token. Same token, two names, both asked.
    : ~ i nosp ( __wh_special t `<|nospeech|>` )
    ? < nosp 0 { = nosp ( __wh_special t `<|nocaptions|>` ) } {}
    ? < lid 0 {
        ( nurl_eprint `whisper: unknown language '` )
        ( nurl_eprint lang )
        ( nurl_eprintln `' — whisper language codes are lowercase two-letter (fi, en, sv, de, …)` )
    } {}
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
    : ~ b silent F
    ~ & ! silent < k ( vec_len [i] prompt ) {
        ?? ( vec_get [i] prompt k ) {
            T tk → { ( wh_decode_step w tk pos ) }
            F → {}
        }
        // The no-speech gate, measured where openai measures it: at the SOT
        // position, BEFORE the language/task tokens condition the model
        // toward producing text. The model is the best voice detector in
        // the building — an energy VAD upstream can be fooled by a phone
        // microphone's auto-gain pumping room noise over the floor, but
        // p(<|nospeech|>) at SOT is not. Past the threshold → this window
        // produces NOTHING, which is the correct amount of "Thank you.".
        ? & & == k 0 >= nosp 0 < nospeech 1.0 {
            : ( Vec f ) lg0 ( wh_logits w )
            : f pn ( __wh_nosp_prob lg0 nosp )
            ( vec_free [f] lg0 )
            ? > pn nospeech { = silent T } {}
        } {}
        = pos + pos 1
        = k + k 1
    }
    ? silent {
        ( vec_free [i] outids )
        ( vec_free [i] prompt )
        ^ T
    } {}
    : ~ b done F
    : ~ i made 0
    : ~ i last -1
    : ~ i last2 -1
    : ~ i mints ts0
    ~ & ! done < made maxtok {
        : ~ i nt 0
        // Greedy decoding wants ONE number out of a step — which logit is
        // largest — and fetching 51865 floats to find out cost more than a
        // third of the step. The constrained timestamp decoding below does
        // need the whole row; plain greedy does not, and does not ask.
        ? with_ts {
            : ( Vec f ) lg ( wh_logits w )
            // openai's exact framing: with FEWER than two sampled tokens the
            // penultimate counts as a timestamp — getting this edge wrong makes
            // the "pair or end" rule fire right after the opening <|0.00|> and
            // the decode ends at one token.
            : b lts & >= made 1 >= last ts0
            : b pts | < made 2 >= last2 ts0
            = nt ( __wh_next_ts lg ts0 eot == made 0 lts pts mints )
            ( vec_free [f] lg )
        } {
            = nt ( wh_argmax_dev w )
        }
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
@ wh_run * Whisper w * Tok t ( Vec f ) at16_in s lang i maxtok b use_vad b with_ts f nospeech ( Vec u ) out → b {
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
        ? ( __wh_decode_window w t lang maxtok with_ts woff runs nospeech out ) {} { = ok F }
        = wi + wi 1
    }
    ( vec_free [f] at16 )
    ( vec_free [VadRun] runs )
    ^ ok
}
