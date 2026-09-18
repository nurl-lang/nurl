// packages/f5tts/src/run.nu — a recording, a transcript and a sentence in;
// a wav out.
//
// The model is only the middle of this. Around it sits a set of rules that
// are not learned and are not documented anywhere except in the reference
// implementation's control flow, and every one of them changes what comes
// out:
//
//   * THE DURATION IS GUESSED, LINEARLY. F5-TTS has no duration model. It
//     assumes the new text will take as long per byte as the reference did:
//
//         frames = ref_frames + ref_frames/ref_bytes · gen_bytes / speed
//
//     That estimate IS the alignment — the text is stretched to exactly that
//     many frames — so it is also the single biggest lever on how the result
//     sounds. Under ten bytes of text the estimate is scaled by 0.3, because
//     a very short utterance given its linear share of the time comes out
//     clipped before the model has settled.
//
//   * THE REFERENCE IS NORMALISED to an rms of 0.1 before the mel and the
//     result is scaled back by the same factor. The model hears a constant
//     loudness whatever the recording was; the caller gets their own back.
//
//   * LONG TEXT IS CUT INTO CHUNKS, by a byte budget derived from the
//     reference's own speaking rate and how much of a 22-second window it
//     already occupies, and the pieces are CROSS-FADED over 150 ms rather
//     than butt-joined.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/path.nu`
$ `deps/hub/src/hub.nu`
$ `deps/audio/src/wav.nu`
$ `deps/audio/src/mel.nu`
$ `deps/audio/src/resample.nu`
$ `model.nu`
$ `sample.nu`
$ `text.nu`
$ `vocos.nu`
$ `verify.nu`

: i F5_SR 24000

: i F5_HOP 256

: f F5_TARGET_RMS 0.1

@ __f5r_get ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// A voice: the reference recording, already at 24 kHz mono and loudness
// normalised, plus its mel and its transcript.
: F5Voice {
    ( Vec f ) mel  // frames × 100
    i frames
    i samples  // of the normalised recording, which sets ref_audio_len
    f rms  // the recording's own loudness, to scale the result back
    f target  // the loudness it was normalised TO, so a cache can tell
    String text
}

@ f5_voice_target * F5Voice v → f { ^ . v target }

@ f5_voice_free * F5Voice v → v {
    ( vec_free [f] . v mel )
    ( string_free . v text )
    ( nurl_free # s v )
}

@ __f5r_err s msg → !*F5Voice String {
    ^ @ !*F5Voice String { F ( string_from msg ) }
}

// F5-TTS insists the reference transcript ends in a sentence break — without
// one the model runs the reference and the new text together as one breath.
@ f5_fix_ref_text s t → String {
    : String out ( string_from t )
    ? ( string_ends_with out `. ` ) { ^ out } {}
    ? ( string_ends_with out `。` ) { ^ out } {}
    ? ( string_ends_with out `.` ) { ( string_push_char out 32 ) ^ out } {}
    ( string_push_str out `. ` )
    ^ out
}

@ f5_voice_load s wav_path s ref_text f target_rms → !*F5Voice String {
    ?? ( wav_read wav_path ) {
        T w → {
            : ( Vec f ) raw ( wav_mono w )
            // the silence split happens at the FILE's own rate, before the
            // resample, exactly where preprocess_ref_audio_text does it
            : ( Vec f ) mono ( f5_prepare_reference raw . w rate )
            ( vec_free [f] raw )
            : i src_n ( vec_len [f] mono )
            ? > src_n 0 {} {
                ( vec_free [f] mono )
                ( wav_free w )
                ^ ( __f5r_err `f5tts: the reference recording is silent` )
            }
            // the loudness is measured before the resample, as the reference does
            : ~ f sum0 0.0
            : ~ i k0 0
            ~ < k0 src_n { : f s ( __f5r_get mono k0 ) = sum0 + sum0 * s s = k0 + k0 1 }
            : f rms0 ( sqrt / sum0 # f src_n )
            // a target of zero or less disables the normalisation entirely,
            // which is what the reference does with a negative target_rms:
            // `if rms < target_rms` is false for every real recording
            ? < rms0 target_rms {
                : f g0 / target_rms ? > rms0 1.0e-12 rms0 1.0e-12
                = k0 0
                ~ < k0 src_n { ( vec_set [f] mono k0 * g0 ( __f5r_get mono k0 ) ) = k0 + k0 1 }
            } {}
            : ( Vec f ) at24 ( resample mono . w rate F5_SR )
            ( vec_free [f] mono )
            ( wav_free w )
            : i n ( vec_len [f] at24 )
            ? > n 0 {} { ( vec_free [f] at24 ) ^ ( __f5r_err `f5tts: the reference recording is empty` ) }
            : f rms rms0
            : ( Vec f ) mel ( log_mel_vocos at24 1024 F5_HOP 100 F5_SR )
            ( vec_free [f] at24 )
            // nurl_alloc does NOT zero, so every field is set here — a field
            // left out is not zero, it is whatever the heap last held, and
            // `target` in particular is DIVIDED BY: a stale huge value scales
            // the finished waveform to 1e-225 and the voice goes silent with
            // nothing else looking wrong.
            : *F5Voice v # *F5Voice ( nurl_alloc Z F5Voice )
            = . v mel mel
            = . v frames / ( vec_len [f] mel ) 100
            = . v samples n
            = . v rms rms
            = . v target target_rms
            = . v text ( f5_fix_ref_text ref_text )
            ^ @ !*F5Voice String { T v }
        }
        F e → { ^ @ !*F5Voice String { F e } }
    }
}

// The voice directory the deployed service uses: config.json holds the
// transcript, reference.wav the recording.
@ f5_voice_open_dir s dir f target_rms → !*F5Voice String {
    : String cfg ( string_from dir )
    ( string_push_str cfg `/config.json` )
    : String wavp ( string_from dir )
    ( string_push_str wavp `/reference.wav` )
    : ~ String txt ( string_new )
    ?? ( read_file ( string_data cfg ) ) {
        T js → {
            ?? ( json_parse ( string_data js ) ) {
                T root → {
                    ?? ( json_obj_get root `ref_text` ) {
                        T node → {
                            = txt ( string_from ( json_as_str node ) )
                        }
                        F → {}
                    }
                    ( json_free root )
                }
                F _e → {}
            }
            ( string_free js )
        }
        F _e → {}
    }
    ( string_free cfg )
    : !*F5Voice String r ( f5_voice_load ( string_data wavp ) ( string_data txt ) target_rms )
    ( string_free wavp )
    ( string_free txt )
    ^ r
}

// ── the byte budget for one chunk ───────────────────────────────────
//
// How much text fits beside a reference of this length inside the 22-second
// window the model was trained on, at the reference's own speaking rate.
@ f5_max_chars * F5Voice v f speed → i {
    : f secs / # f . v samples # f F5_SR
    : i rb ( nurl_str_len ( string_data . v text ) )
    : f room - 22.0 secs
    ? < room 0.0 { ^ 1 } {}
    : i mc # i * / # f rb secs * room speed
    ? < mc 1 { ^ 1 } {}
    ^ mc
}

// The frame count F5-TTS will generate for one chunk. `gen_bytes` is the new
// text's length in BYTES, not characters — a Finnish umlaut counts twice, and
// that is the reference implementation's own arithmetic, not an oversight
// this port kept.
// Off by default: the reference implementation's rule is one line, and a port
// that quietly used a different one would not be a port. What turning it on
// does, and why it exists, is in the comment inside f5_duration.
: ~ b g_f5r_shortfix F

@ f5_short_fix b on → v { = g_f5r_shortfix on }

@ f5_short_fix_on → b { ^ g_f5r_shortfix }

: i F5_SHORT_PLUS_MS 1100

: i F5_SHORT_FULL_BYTES 30

: i F5_SHORT_TAPER_END 120

@ f5_duration * F5Voice v s gen_text i n_text f speed → i {
    : i gen_bytes ( nurl_str_len gen_text )
    : ~ f local speed
    ? g_f5r_shortfix {} {
        ? < gen_bytes 10 { = local 0.3 } {}
    }
    : i ref_audio_len / . v samples F5_HOP
    : i rb ( nurl_str_len ( string_data . v text ) )
    : ~ i d ref_audio_len
    ? > rb 0 {
        = d + ref_audio_len # i / * / # f ref_audio_len # f rb # f gen_bytes local
    } {}
    ? g_f5r_shortfix {
        // The reference's estimate is a speaking RATE, and a short line is
        // mostly not speaking: an onset, a word or two, a close. Measured on
        // this checkpoint with two voices and eleven one-to-three-word lines
        // (packages/f5tts, 2026-09-17): at 0.8 s of generated audio they
        // come back as silence, at 1.2 s clipped ("Kiitos itselle"), at
        // 1.6-2.0 s right, and at 2.5 s and over the model fills the room by
        // saying the line twice or carrying on with the reference text. So a
        // short line gets its linear estimate plus a fixed overhead — 1.1 s
        // up to thirty bytes, tapering to nothing at a hundred and twenty,
        // where the estimate is already a few seconds and stands on its own.
        ? < gen_bytes F5_SHORT_TAPER_END {
            : ~ i plus_ms F5_SHORT_PLUS_MS
            ? > gen_bytes F5_SHORT_FULL_BYTES {
                = plus_ms / * F5_SHORT_PLUS_MS - F5_SHORT_TAPER_END gen_bytes - F5_SHORT_TAPER_END F5_SHORT_FULL_BYTES
            } {}
            = d + d / / * plus_ms F5_SR 1000 F5_HOP
        } {}
    } {}
    // at least the text's own length, and at least the conditioning, plus one
    : i floor1 + ? > n_text . v frames n_text . v frames 1
    ? < d floor1 { = d floor1 } {}
    ? > d 4096 { = d 4096 } {}
    ^ d
}

@ f5_ref_audio_len * F5Voice v → i { ^ / . v samples F5_HOP }

// ── one chunk ───────────────────────────────────────────────────────

@ __f5r_synth_once * F5Model m * Vocos vc * F5Voice v * F5Vocab vocab s gen_text
i steps f cfg f sway f speed i seed ( Vec f ) out → b {
    : ( Vec i ) ids ( vec_new [i] )
    : String full ( string_clone . v text )
    ( string_push_str full gen_text )
    ( f5_text_ids vocab ( string_data full ) ids )
    ( string_free full )
    : i duration ( f5_duration v gen_text ( vec_len [i] ids ) speed )
    : ( Vec f ) noise ( f5_noise duration 100 seed )
    : ( Vec f ) y ( vec_new [f] )
    : b ok ( f5_sample m ids duration . v mel steps cfg sway noise y )
    ( vec_free [f] noise )
    ( vec_free [i] ids )
    ? ok {} { ( vec_free [f] y ) ^ F }
    // the conditioned frames go back over the trajectory before the cut
    : i cf * . v frames 100
    : ~ i k 0
    ~ < k cf { ( vec_set [f] y k ( __f5r_get . v mel k ) ) = k + k 1 }
    : i ral ( f5_ref_audio_len v )
    : i gen_frames - duration ral
    : ( Vec f ) gmel ( vec_with_cap [f] * gen_frames 100 )
    = k 0
    ~ < k * gen_frames 100 { ( vec_push [f] gmel ( __f5r_get y + * ral 100 k ) ) = k + k 1 }
    ( vec_free [f] y )
    : b vok ( voc_decode vc gmel gen_frames out )
    ( vec_free [f] gmel )
    ? vok {} { ^ F }
    // and the loudness the caller's own recording had
    ? < . v rms . v target {
        : f g / . v rms . v target
        = k 0
        ~ < k ( vec_len [f] out ) { ( vec_set [f] out k * g ( __f5r_get out k ) ) = k + k 1 }
    } {}
    ^ T
}

// ── generate, listen, and try again ─────────────────────────────────
//
// The model has no idea whether it said the words. So when a transcriber is
// configured, the chunk is generated, transcribed and scored, and a score
// over the threshold buys another attempt from a different seed — `retries`
// of them, so a line is generated at most 1 + retries times. The BEST
// attempt is kept, not the last: a retry can come out worse, and returning
// the worse one because it came later would make the feature harmful.
//
// A transcription that fails to happen — no server, a timeout — is not an
// error rate of one. It is no information, and the first attempt stands.
//
// What the gate found out travels in a score: four integers — word errors,
// reference words, the most attempts any chunk needed, and the chunks the
// transcriber never answered for. The words stay zero when nothing was
// transcribed, so "unchecked" and "perfect" are different answers, and an
// unheard chunk is counted rather than passed off as fine.

@ f5_score_new → ( Vec i ) {
    : ( Vec i ) s ( vec_with_cap [i] 4 )
    ( vec_push [i] s 0 )
    ( vec_push [i] s 0 )
    ( vec_push [i] s 0 )
    ( vec_push [i] s 0 )
    ^ s
}

@ f5_score_errs ( Vec i ) s → i { ^ ( _f5t_geti s 0 ) }

@ f5_score_words ( Vec i ) s → i { ^ ( _f5t_geti s 1 ) }

@ f5_score_attempts ( Vec i ) s → i { ^ ( _f5t_geti s 2 ) }

@ f5_score_unheard ( Vec i ) s → i { ^ ( _f5t_geti s 3 ) }

@ f5_score_checked ( Vec i ) s → b { ^ > ( _f5t_geti s 1 ) 0 }

// The word error rate the score stands for, or -1 when nothing was checked.
@ f5_score_wer ( Vec i ) s → f {
    : i w ( _f5t_geti s 1 )
    ? > w 0 {} { ^ -1.0 }
    ^ / # f ( _f5t_geti s 0 ) # f w
}

@ __f5r_score_add ( Vec i ) s i errs i words i attempts → v {
    ( vec_set [i] s 0 + ( _f5t_geti s 0 ) errs )
    ( vec_set [i] s 1 + ( _f5t_geti s 1 ) words )
    ? > attempts ( _f5t_geti s 2 ) { ( vec_set [i] s 2 attempts ) } {}
}

@ __f5r_score_unheard ( Vec i ) s → v { ( vec_set [i] s 3 + ( _f5t_geti s 3 ) 1 ) }

@ f5_score_merge ( Vec i ) into ( Vec i ) from → v {
    ( __f5r_score_add into ( _f5t_geti from 0 ) ( _f5t_geti from 1 ) ( _f5t_geti from 2 ) )
    ( vec_set [i] into 3 + ( _f5t_geti into 3 ) ( _f5t_geti from 3 ) )
}

// Is the gate on at all for these settings? A transcriber, and something
// that could act on its answer.
@ f5_gate_on i retries f max_wer → b {
    ? ( f5_whisper_enabled ) {} { ^ F }
    ^ | > retries 0 < max_wer 1.0
}

// The transcriber's word errors against `gen_text`, or -1 when it had
// nothing to say. A transcriber that is busy with someone else's request,
// or reloading its weights, answers with nothing for a moment — so an empty
// answer is asked again, a few times, before it counts as no answer.
: i F5_LISTEN_TRIES 4

@ __f5r_listen s gen_text ( Vec f ) wave → i {
    : ~ i t 0
    ~ < t F5_LISTEN_TRIES {
        : String heard ( f5_transcribe wave )
        ? > ( string_len heard ) 0 {
            : i e ( f5_errors gen_text ( string_data heard ) )
            ( string_free heard )
            ^ e
        } {}
        ( string_free heard )
        = t + t 1
        ? < t F5_LISTEN_TRIES { ( sleep_ms * 500 t ) } {}
    }
    ( nurl_eprintln `f5tts: the transcriber did not answer; this chunk goes unchecked` )
    ^ -1
}

@ __f5r_copy ( Vec f ) dst ( Vec f ) src → v {
    ( vec_clear [f] dst )
    : ~ i k 0
    ~ < k ( vec_len [f] src ) {
        ( vec_push [f] dst ( __f5r_get src k ) )
        = k + k 1
    }
}

@ f5_synth_chunk * F5Model m * Vocos vc * F5Voice v * F5Vocab vocab s gen_text
i steps f cfg f sway f speed i seed i retries f max_wer ( Vec f ) out ( Vec i ) score → b {
    : ~ b ok ( __f5r_synth_once m vc v vocab gen_text steps cfg sway speed seed out )
    ? ok {} { ^ F }
    ? ( f5_gate_on retries max_wer ) {} { ^ T }
    : i nw ( f5_word_count_norm gen_text )
    ? > nw 0 {} { ^ T }
    : ~ i best ( __f5r_listen gen_text out )
    ? >= best 0 {} { ( __f5r_score_unheard score ) ^ T }
    : f allowed * max_wer # f nw
    : ~ i att 1
    ? <= # f best allowed {
        ( __f5r_score_add score best nw att )
        ^ T
    } {}
    : ( Vec f ) try ( vec_new [f] )
    ~ & <= att retries > # f best allowed {
        ( vec_clear [f] try )
        ? ( __f5r_synth_once m vc v vocab gen_text steps cfg sway speed + seed * 7919 att try ) {
            : i e2 ( __f5r_listen gen_text try )
            ? & >= e2 0 < e2 best {
                = best e2
                ( __f5r_copy out try )
            } {}
        } {}
        = att + att 1
    }
    ( vec_free [f] try )
    ? > # f best allowed {
        : String msg ( string_from `f5tts: kept the best of ` )
        ( string_push_int msg att )
        ( string_push_str msg ` attempts, ` )
        ( string_push_int msg best )
        ( string_push_str msg ` of ` )
        ( string_push_int msg nw )
        ( string_push_str msg ` words wrong: ` )
        ( string_push_str msg gen_text )
        ( nurl_eprintln ( string_data msg ) )
        ( string_free msg )
    } {}
    ( __f5r_score_add score best nw att )
    ^ T
}

// ── the whole utterance ─────────────────────────────────────────────

// Join `next` onto `acc` with a linear cross-fade over `fade` samples.
@ f5_crossfade ( Vec f ) acc ( Vec f ) next i fade → v {
    : i na ( vec_len [f] acc )
    : i nb ( vec_len [f] next )
    ? == na 0 {
        : ~ i k 0
        ~ < k nb { ( vec_push [f] acc ( __f5r_get next k ) ) = k + k 1 }
        ^ v
    } {}
    : ~ i cf fade
    ? > cf na { = cf na } {}
    ? > cf nb { = cf nb } {}
    ? <= cf 0 {
        : ~ i k 0
        ~ < k nb { ( vec_push [f] acc ( __f5r_get next k ) ) = k + k 1 }
        ^ v
    } {}
    : ~ i k 0
    ~ < k cf {
        : f w / # f k # f - cf 1
        : i ai + - na cf k
        ( vec_set [f] acc ai + * ( __f5r_get acc ai ) - 1.0 w * ( __f5r_get next k ) w )
        = k + k 1
    }
    = k cf
    ~ < k nb { ( vec_push [f] acc ( __f5r_get next k ) ) = k + k 1 }
}

@ f5_synth * F5Model m * Vocos vc * F5Voice v * F5Vocab vocab s gen_text
i steps f cfg f sway f speed f fade_s i seed ( Vec f ) out → b {
    : ( Vec i ) score ( f5_score_new )
    : b ok ( f5_synth_scored m vc v vocab gen_text steps cfg sway speed fade_s seed 0 1.0 out score )
    ( vec_free [i] score )
    ^ ok
}

// A line that opens with a one-word sentence — "Juuri. Seuraavaksi ne
// tuo…" — loses it: the model runs the reference straight into the second
// sentence and the first is never said, from every seed. Said on its own
// the same word comes out fine. So under --short-fix a one-word opening
// sentence is its own chunk, with its own duration estimate. Two-word
// openings ("Eipä kestä.", "Kiitos kutsusta.") were said as part of the
// line and are left in it. Returns where the rest begins, or 0 when the
// rule does not apply.
: i F5_LEAD_WORDS 1

@ _f5r_lead_split s text → i {
    : i n ( nurl_str_len text )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get text k )
        ? & | == c 46 | == c 33 == c 63 < + k 1 n {
            ? ( __f5r_is_ws ( nurl_str_get text + k 1 ) ) {
                : ~ i e + k 1
                ~ & < e n ( __f5r_is_ws ( nurl_str_get text e ) ) { = e + e 1 }
                ? >= e n { ^ 0 } {}
                : String head ( string_from ( nurl_str_slice text 0 + k 1 ) )
                : i wc ( f5_word_count ( string_data head ) )
                ( string_free head )
                ^ ? <= wc F5_LEAD_WORDS e 0
            } {}
        } {}
        = k + k 1
    }
    ^ 0
}

@ __f5r_chunks * F5Voice v s gen_text f speed → ( Vec String ) {
    : i mc ( f5_max_chars v speed )
    : ( Vec String ) chunks ( f5_chunk_text gen_text mc )
    ? g_f5r_shortfix {} { ^ chunks }
    ? > ( vec_len [String] chunks ) 0 {} { ^ chunks }
    ?? ( vec_get [String] chunks 0 ) {
        T first → {
            : i at ( _f5r_lead_split ( string_data first ) )
            ? > at 0 {
                : String lead ( string_trim ( string_from ( nurl_str_slice ( string_data first ) 0 at ) ) )
                : String rest ( string_trim ( string_from ( nurl_str_slice ( string_data first ) at - ( string_len first ) at ) ) )
                ( vec_set [String] chunks 0 lead )
                : b _i ( vec_insert [String] chunks 1 rest )
                ( string_free first )
            } {}
        }
        F → {}
    }
    ^ chunks
}

// The utterance, chunk by chunk, each through the gate: `retries` more
// attempts for a chunk whose word error rate is over `max_wer`, and the
// score of what was kept added to `score`.
@ f5_synth_scored * F5Model m * Vocos vc * F5Voice v * F5Vocab vocab s gen_text
i steps f cfg f sway f speed f fade_s i seed i retries f max_wer ( Vec f ) out ( Vec i ) score → b {
    : ( Vec String ) chunks ( __f5r_chunks v gen_text speed )
    : i nc ( vec_len [String] chunks )
    : i fade # i * fade_s # f F5_SR
    : ~ b ok T
    : ~ i k 0
    ~ < k nc {
        ?? ( vec_get [String] chunks k ) {
            T c → {
                : ( Vec f ) piece ( vec_new [f] )
                = ok & ok ( f5_synth_chunk m vc v vocab ( string_data c ) steps cfg sway speed
                + seed k retries max_wer piece score )
                ? ok { ( f5_crossfade out piece fade ) } {}
                ( vec_free [f] piece )
            }
            F → {}
        }
        = k + k 1
    }
    : ( @ v String ) drop_c \ String s → v { ( string_free s ) }
    ( vec_free_with [String] chunks drop_c )
    ^ ok
}

// Scale a waveform down, once, if it would clip on the way to 16 bits.
// The model's output is louder than its reference for some voices, and
// with target_rms off nothing else stands between it and the encoder.
@ f5_limit_peak ( Vec f ) wave → v {
    : ~ f peak 0.0
    : i n ( vec_len [f] wave )
    : ~ i k 0
    ~ < k n {
        : f a ( fabs ( __f5r_get wave k ) )
        ? > a peak { = peak a } {}
        = k + k 1
    }
    ? > peak 0.99 {} { ^ v }
    : f g / 0.99 peak
    = k 0
    ~ < k n { ( vec_set [f] wave k * g ( __f5r_get wave k ) ) = k + k 1 }
}

// ── preparing the reference recording ───────────────────────────────
//
// F5-TTS does not feed a recording to the model as it finds it. It splits it
// on silence, keeps as much as fits in twelve seconds, trims the edges and
// appends fifty milliseconds of quiet — and every one of those steps is load
// bearing, because the reference IS the voice: whatever is in it, including
// its leading breath and its room tone, is what the model imitates.
//
// The reference implementation does this through pydub, in milliseconds, on
// integer samples. The arithmetic below is the same arithmetic on floats:
// pydub's dBFS is 20·log10(rms / 32768) and a float sample is already that
// ratio, so a threshold in dBFS compares directly against 10^(dB/20).

@ __f5r_rms ( Vec f ) x i from i to → f {
    : i n ( vec_len [f] x )
    : i a ? < from 0 0 from
    : i b ? > to n n to
    ? >= a b { ^ 0.0 } {}
    : ~ f s 0.0
    : ~ i k a
    ~ < k b { : f v ( __f5r_get x k ) = s + s * v v = k + k 1 }
    ^ ( sqrt / s # f - b a )
}

@ __f5r_ms2s i ms i rate → i { ^ / * ms rate 1000 }

// pydub's detect_silence, as [start_ms, end_ms) pairs.
@ __f5r_silences ( Vec f ) x i rate i min_ms f thresh_db i seek_ms → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : i n ( vec_len [f] x )
    : i seg_ms / * n 1000 rate
    ? < seg_ms min_ms { ^ out } {}
    : f thresh ( pow 10.0 / thresh_db 20.0 )
    : ( Vec i ) starts ( vec_new [i] )
    : i last - seg_ms min_ms
    : ~ i i 0
    ~ <= i last {
        : i a ( __f5r_ms2s i rate )
        : i b ( __f5r_ms2s + i min_ms rate )
        ? <= ( __f5r_rms x a b ) thresh { ( vec_push [i] starts i ) } {}
        = i + i seek_ms
    }
    // pydub always examines the final window, even when seek_step steps over it
    ? != 0 % last seek_ms {
        : i a ( __f5r_ms2s last rate )
        : i b ( __f5r_ms2s + last min_ms rate )
        ? <= ( __f5r_rms x a b ) thresh { ( vec_push [i] starts last ) } {}
    } {}
    : i ns ( vec_len [i] starts )
    ? == ns 0 { ( vec_free [i] starts ) ^ out } {}
    : ~ i prev ( _f5t_geti starts 0 )
    : ~ i cur prev
    : ~ i k 1
    ~ < k ns {
        : i si ( _f5t_geti starts k )
        : b continuous == si + prev seek_ms
        : b gap > si + prev min_ms
        ? & ! continuous gap {
            ( vec_push [i] out cur )
            ( vec_push [i] out + prev min_ms )
            = cur si
        } {}
        = prev si
        = k + k 1
    }
    ( vec_push [i] out cur )
    ( vec_push [i] out + prev min_ms )
    ( vec_free [i] starts )
    ^ out
}

// pydub's split_on_silence, as [start_ms, end_ms) pairs of KEPT audio.
@ __f5r_nonsilent ( Vec f ) x i rate i min_ms f thresh_db i keep_ms i seek_ms → ( Vec i ) {
    : ( Vec i ) sil ( __f5r_silences x rate min_ms thresh_db seek_ms )
    : i n ( vec_len [f] x )
    : i seg_ms / * n 1000 rate
    : ( Vec i ) ns ( vec_new [i] )
    : i np ( vec_len [i] sil )
    ? == np 0 {
        ( vec_push [i] ns 0 )
        ( vec_push [i] ns seg_ms )
    } {
        : ~ i prev 0
        : ~ i k 0
        ~ < k np {
            : i s ( _f5t_geti sil k )
            : i e ( _f5t_geti sil + k 1 )
            ? > s prev { ( vec_push [i] ns prev ) ( vec_push [i] ns s ) } {}
            = prev e
            = k + k 2
        }
        ? < prev seg_ms { ( vec_push [i] ns prev ) ( vec_push [i] ns seg_ms ) } {}
    }
    ( vec_free [i] sil )
    // widen by keep_silence, then split any overlap down the middle
    : i nn ( vec_len [i] ns )
    : ~ i k 0
    ~ < k nn {
        ( vec_set [i] ns k - ( _f5t_geti ns k ) keep_ms )
        ( vec_set [i] ns + k 1 + ( _f5t_geti ns + k 1 ) keep_ms )
        = k + k 2
    }
    = k 0
    ~ < k - nn 2 {
        : i le ( _f5t_geti ns + k 1 )
        : i ns2 ( _f5t_geti ns + k 2 )
        ? < ns2 le {
            : i mid / + le ns2 2
            ( vec_set [i] ns + k 1 mid )
            ( vec_set [i] ns + k 2 mid )
        } {}
        = k + k 2
    }
    ^ ns
}

// pydub's remove_silence_edges: leading silence in 10 ms chunks, trailing in
// 1 ms ones, both against -42 dBFS.
@ __f5r_trim_edges ( Vec f ) x i rate → ( Vec f ) {
    : i n ( vec_len [f] x )
    : f thresh ( pow 10.0 / -42.0 20.0 )
    : i chunk ( __f5r_ms2s 10 rate )
    : ~ i start 0
    ~ & < start n < ( __f5r_rms x start + start chunk ) thresh { = start + start chunk }
    ? >= start n { = start n } {}
    : i one ( __f5r_ms2s 1 rate )
    : ~ i end n
    ~ & > end + start one <= ( __f5r_rms x - end one end ) thresh { = end - end one }
    : ( Vec f ) out ( vec_new [f] )
    : ~ i k start
    ~ < k end { ( vec_push [f] out ( __f5r_get x k ) ) = k + k 1 }
    ^ out
}

// The whole of preprocess_ref_audio_text's audio half.
@ f5_prepare_reference ( Vec f ) x i rate → ( Vec f ) {
    : ( Vec f ) first ( __f5r_take_segments x rate 1000 -50.0 1000 10 )
    : ~ ( Vec f ) kept first
    : i ms12 ( __f5r_ms2s 12000 rate )
    ? > ( vec_len [f] kept ) ms12 {
        // the long-silence pass did not find a cut: try short pauses
        : ( Vec f ) second ( __f5r_take_segments x rate 100 -40.0 1000 10 )
        ( vec_free [f] first )
        = kept second
    } {}
    ? > ( vec_len [f] kept ) ms12 {
        : ( Vec f ) cut ( vec_with_cap [f] ms12 )
        : ~ i k 0
        ~ < k ms12 { ( vec_push [f] cut ( __f5r_get kept k ) ) = k + k 1 }
        ( vec_free [f] kept )
        = kept cut
    } {}
    ? == 0 ( vec_len [f] kept ) {
        // nothing survived: the recording is all silence by these thresholds,
        // and its own samples are a better reference than none
        ( vec_free [f] kept )
        : ( Vec f ) all ( vec_with_cap [f] ( vec_len [f] x ) )
        : ~ i k 0
        ~ < k ( vec_len [f] x ) { ( vec_push [f] all ( __f5r_get x k ) ) = k + k 1 }
        = kept all
    } {}
    : ( Vec f ) trimmed ( __f5r_trim_edges kept rate )
    ( vec_free [f] kept )
    // fifty milliseconds of quiet, so the model does not start mid-breath
    : i pad ( __f5r_ms2s 50 rate )
    : ~ i k 0
    ~ < k pad { ( vec_push [f] trimmed 0.0 ) = k + k 1 }
    ^ trimmed
}

// Concatenate non-silent segments while they fit: stop once six seconds are
// in hand and the next one would take it past twelve.
@ __f5r_take_segments ( Vec f ) x i rate i min_ms f thresh_db i keep_ms i seek_ms → ( Vec f ) {
    : ( Vec i ) ns ( __f5r_nonsilent x rate min_ms thresh_db keep_ms seek_ms )
    : i n ( vec_len [f] x )
    : ( Vec f ) out ( vec_new [f] )
    : i ms6 ( __f5r_ms2s 6000 rate )
    : i ms12 ( __f5r_ms2s 12000 rate )
    : i np ( vec_len [i] ns )
    : ~ i k 0
    ~ < k np {
        : i a0 ( _f5t_geti ns k )
        : i b0 ( _f5t_geti ns + k 1 )
        : i a ? < ( __f5r_ms2s a0 rate ) 0 0 ( __f5r_ms2s a0 rate )
        : i b ? > ( __f5r_ms2s b0 rate ) n n ( __f5r_ms2s b0 rate )
        : i have ( vec_len [f] out )
        ? & > have ms6 > + have - b a ms12 { = k np } {
            : ~ i j a
            ~ < j b { ( vec_push [f] out ( __f5r_get x j ) ) = j + j 1 }
            = k + k 2
        }
    }
    ( vec_free [i] ns )
    ^ out
}

// ── finding the weights ─────────────────────────────────────────────
//
// A checkpoint argument is a local file, a local directory holding one, or a
// repository reference — `owner/repo/path/to/model.safetensors`
// names a single file in a repo and is fetched into the shared ~/.nurl cache.
// The vocabulary is looked for beside whatever the checkpoint turned out to
// be, because that is where every F5-TTS release puts it.

@ __f5r_find_ext s dir s ext i depth → String {
    : String found ( string_new )
    ?? ( dir_list dir ) {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? == 0 ( string_len found ) {
                            : String p ( string_from dir )
                            ( string_push_char p 47 )
                            ( string_push_str p ( string_data nm ) )
                            ? ( string_ends_with nm ext ) {
                                ( string_push_str found ( string_data p ) )
                            } {
                                ? > depth 0 {
                                    : String sub ( __f5r_find_ext ( string_data p ) ext - depth 1 )
                                    ? > ( string_len sub ) 0 {
                                        ( string_push_str found ( string_data sub ) )
                                    } {}
                                    ( string_free sub )
                                } {}
                            }
                            ( string_free p )
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
            : ( @ v String ) drop_s \ String s → v { ( string_free s ) }
            ( vec_free_with [String] names drop_s )
        }
        F _e → {}
    }
    ^ found
}

@ f5_resolve_file s arg s ext → String {
    ? == 0 ( nurl_str_len arg ) { ^ ( string_new ) } {}
    ? ( file_exists arg ) {
        : String d ( __f5r_find_ext arg ext 2 )
        ? > ( string_len d ) 0 { ^ d } {}
        ( string_free d )
        ^ ( string_from arg )
    } {}
    ?? ( hub_get arg ) {
        T p → {
            : String d ( __f5r_find_ext ( string_data p ) ext 2 )
            ? > ( string_len d ) 0 { ( string_free p ) ^ d } {}
            ( string_free d )
            ^ p
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ ( string_new )
        }
    }
}

// vocab.txt beside the checkpoint, unless one was named.
@ f5_resolve_vocab s arg s model_path → String {
    ? != 0 ( nurl_str_len arg ) { ^ ( f5_resolve_file arg `.txt` ) } {}
    : String dir ( path_dirname model_path )
    : String p ( string_from ( string_data dir ) )
    ( string_free dir )
    ( string_push_str p `/vocab.txt` )
    ? ( file_exists ( string_data p ) ) { ^ p } {}
    ( string_free p )
    ^ ( string_new )
}

// ── what a dialogue line is made of ─────────────────────────────────
//
// Above the chunking there is a second layer of splitting, and it belongs to
// the dialogue rather than to the model. A line is first stripped of its
// stage directions — "[laughs]" is for the reader, not the speaker — and then,
// if it runs to more than six sentences, generated a sentence at a time with
// sixty milliseconds of silence between them. A line that ends in ".." or
// "..." gets a real pause after it, because the model does not read the dots
// as time.

: i F5_MIN_SPLIT_WORDS 5

@ f5_strip_brackets s text → String {
    : String out ( string_new )
    : i n ( nurl_str_len text )
    : ~ i depth 0
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get text k )
        ? == c 91 { = depth + depth 1 } {
            ? == c 93 { ? > depth 0 { = depth - depth 1 } {} } {
                ? == depth 0 { ( string_push_char out c ) } {}
            }
        }
        = k + k 1
    }
    ^ ( string_trim out )
}

// Sentences, split at . ! ? followed by whitespace, with anything under five
// words merged into its neighbour — a two-word sentence given a duration
// estimate of its own is exactly the case the model fumbles.
@ f5_split_sentences s text → ( Vec String ) {
    : ( Vec String ) raw ( vec_new [String] )
    : i n ( nurl_str_len text )
    : ~ i start 0
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get text k )
        ? | == c 46 | == c 33 == c 63 {
            ? & < + k 1 n ( __f5r_is_ws ( nurl_str_get text + k 1 ) ) {
                : ~ i e + k 1
                ~ & < e n ( __f5r_is_ws ( nurl_str_get text e ) ) { = e + e 1 }
                : String piece ( string_from ( nurl_str_slice text start - + k 1 start ) )
                : String tp ( string_trim piece )
                ? > ( string_len tp ) 0 { ( vec_push [String] raw tp ) } { ( string_free tp ) }
                ( string_free piece )
                = start e
                = k e
            } { = k + k 1 }
        } { = k + k 1 }
    }
    ? < start n {
        : String piece ( string_from ( nurl_str_slice text start - n start ) )
        : String tp ( string_trim piece )
        ? > ( string_len tp ) 0 { ( vec_push [String] raw tp ) } { ( string_free tp ) }
        ( string_free piece )
    } {}
    : ( Vec String ) merged ( vec_new [String] )
    : String buf ( string_new )
    : i nr ( vec_len [String] raw )
    = k 0
    ~ < k nr {
        ?? ( vec_get [String] raw k ) {
            T sp → {
                ? > ( string_len buf ) 0 { ( string_push_char buf 32 ) } {}
                ( string_push_str buf ( string_data sp ) )
                ? >= ( f5_word_count ( string_data buf ) ) F5_MIN_SPLIT_WORDS {
                    ( vec_push [String] merged ( string_clone buf ) )
                    ( string_clear buf )
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ? > ( string_len buf ) 0 {
        : i nm ( vec_len [String] merged )
        ? > nm 0 {
            ?? ( vec_get [String] merged - nm 1 ) {
                T last → {
                    : String joined ( string_clone last )
                    ( string_push_char joined 32 )
                    ( string_push_str joined ( string_data buf ) )
                    ( vec_set [String] merged - nm 1 joined )
                    ( string_free last )
                }
                F → {}
            }
        } { ( vec_push [String] merged ( string_clone buf ) ) }
    } {}
    ( string_free buf )
    : ( @ v String ) drop_r \ String s → v { ( string_free s ) }
    ( vec_free_with [String] raw drop_r )
    ^ merged
}

@ __f5r_is_ws i c → b {
    ? == c 32 { ^ T } {}
    ^ & >= c 9 <= c 13
}

@ f5_word_count s text → i {
    : i n ( nurl_str_len text )
    : ~ i count 0
    : ~ b inword F
    : ~ i k 0
    ~ < k n {
        : b ws ( __f5r_is_ws ( nurl_str_get text k ) )
        ? ws { = inword F } { ? inword {} { = count + count 1 = inword T } }
        = k + k 1
    }
    ^ count
}

// Milliseconds of silence a line's own punctuation asks for.
@ f5_trailing_pause_ms s text → i {
    : String t ( string_trim ( string_from text ) )
    : i n ( string_len t )
    : ~ i ms 0
    ? >= n 3 {
        ? & & == 46 ( nurl_str_get ( string_data t ) - n 1 )
        == 46 ( nurl_str_get ( string_data t ) - n 2 )
        == 46 ( nurl_str_get ( string_data t ) - n 3 ) { = ms 800 } {}
    } {}
    ? & == ms 0 >= n 2 {
        ? & == 46 ( nurl_str_get ( string_data t ) - n 1 )
        == 46 ( nurl_str_get ( string_data t ) - n 2 ) { = ms 400 } {}
    } {}
    ( string_free t )
    ^ ms
}

@ f5_append_silence ( Vec f ) out i ms → v {
    : i k0 / * ms F5_SR 1000
    : ~ i k 0
    ~ < k k0 { ( vec_push [f] out 0.0 ) = k + k 1 }
}

// One dialogue line: the stage directions removed, split into sentences when
// there are more than six of them, each generated with the quality gate, and
// joined with the sixty-millisecond pause the reference service uses.
//
// `splitfail` is the reference service's second remedy: when the line as a
// whole is still over `max_wer` after at least `splitfail` attempts, it is
// generated again a sentence at a time, each sentence through the gate, and
// whichever of the two came out with fewer errors is kept. Zero turns it off.
@ __f5r_synth_sentences * F5Model m * Vocos vc * F5Voice v * F5Vocab vocab ( Vec String ) sents
i steps f cfg f sway f speed f fade_s i seed i retries f max_wer ( Vec f ) out ( Vec i ) score → b {
    : i ns ( vec_len [String] sents )
    : ~ b ok T
    : ~ i k 0
    ~ & < k ns ok {
        ?? ( vec_get [String] sents k ) {
            T sp → {
                : ( Vec f ) piece ( vec_new [f] )
                = ok ( f5_synth_scored m vc v vocab ( string_data sp ) steps cfg sway
                speed fade_s + seed k retries max_wer piece score )
                ? ok {
                    : ~ i j 0
                    ~ < j ( vec_len [f] piece ) {
                        ( vec_push [f] out ( __f5r_get piece j ) )
                        = j + j 1
                    }
                    ? < k - ns 1 { ( f5_append_silence out 60 ) } {}
                } {}
                ( vec_free [f] piece )
            }
            F → {}
        }
        = k + k 1
    }
    ^ ok
}

@ f5_synth_line * F5Model m * Vocos vc * F5Voice v * F5Vocab vocab s text
i steps f cfg f sway f speed f fade_s i seed i retries f max_wer i splitfail ( Vec f ) out ( Vec i ) score → b {
    : String clean ( f5_strip_brackets text )
    ? > ( string_len clean ) 0 {} { ( string_free clean ) ^ T }
    : ( Vec String ) sents ( f5_split_sentences ( string_data clean ) )
    : i ns ( vec_len [String] sents )
    : ~ b ok T
    ? > ns 6 {
        = ok ( __f5r_synth_sentences m vc v vocab sents steps cfg sway speed fade_s seed
        retries max_wer out score )
    } {
        : ( Vec i ) s1 ( f5_score_new )
        : ( Vec f ) whole ( vec_new [f] )
        = ok ( f5_synth_scored m vc v vocab ( string_data clean ) steps cfg sway speed
        fade_s seed retries max_wer whole s1 )
        : b failed & ( f5_score_checked s1 ) > ( f5_score_wer s1 ) max_wer
        ? & & ok failed & > splitfail 0 & >= ( f5_score_attempts s1 ) splitfail > ns 1 {
            : ( Vec i ) s2 ( f5_score_new )
            : ( Vec f ) split ( vec_new [f] )
            : b ok2 ( __f5r_synth_sentences m vc v vocab sents steps cfg sway speed fade_s
            + seed 1000 retries max_wer split s2 )
            // fewer errors, and every sentence actually heard — a result
            // the transcriber went quiet on is not a better one
            : b better & & ok2 == ( f5_score_unheard s2 ) 0 < ( f5_score_wer s2 ) ( f5_score_wer s1 )
            : String msg ( string_from `f5tts: split into ` )
            ( string_push_int msg ns )
            ( string_push_str msg ` sentences after ` )
            ( string_push_int msg ( f5_score_attempts s1 ) )
            ( string_push_str msg ` attempts: ` )
            ( string_push_int msg ( f5_score_errs s2 ) )
            ( string_push_str msg ` errors against ` )
            ( string_push_int msg ( f5_score_errs s1 ) )
            ( string_push_str msg ? better `, kept the sentences` `, kept the whole line` )
            ( nurl_eprintln ( string_data msg ) )
            ( string_free msg )
            ? better {
                ( __f5r_copy whole split )
                ( vec_set [i] s1 0 ( f5_score_errs s2 ) )
                ( vec_set [i] s1 1 ( f5_score_words s2 ) )
                ( vec_set [i] s1 2 ( f5_score_attempts s2 ) )
                ( vec_set [i] s1 3 ( f5_score_unheard s2 ) )
            } {}
            ( vec_free [f] split )
            ( vec_free [i] s2 )
        } {}
        : ~ i j 0
        ~ < j ( vec_len [f] whole ) {
            ( vec_push [f] out ( __f5r_get whole j ) )
            = j + j 1
        }
        ( f5_score_merge score s1 )
        ( vec_free [f] whole )
        ( vec_free [i] s1 )
    }
    ( f5_append_silence out ( f5_trailing_pause_ms ( string_data clean ) ) )
    : ( @ v String ) drop_s \ String s → v { ( string_free s ) }
    ( vec_free_with [String] sents drop_s )
    ( string_free clean )
    ^ ok
}

@ f5_voice_rms * F5Voice v → f { ^ . v rms }
