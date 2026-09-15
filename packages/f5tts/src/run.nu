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
$ `deps/audio/src/wav.nu`
$ `deps/audio/src/mel.nu`
$ `deps/audio/src/resample.nu`
$ `model.nu`
$ `sample.nu`
$ `text.nu`
$ `vocos.nu`

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
    String text
}

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

@ f5_voice_load s wav_path s ref_text → !*F5Voice String {
    ?? ( wav_read wav_path ) {
        T w → {
            : ( Vec f ) mono ( wav_mono w )
            : ( Vec f ) at24 ( resample mono . w rate F5_SR )
            ( vec_free [f] mono )
            ( wav_free w )
            : i n ( vec_len [f] at24 )
            ? > n 0 {} { ( vec_free [f] at24 ) ^ ( __f5r_err `f5tts: the reference recording is empty` ) }
            : ~ f sum 0.0
            : ~ i k 0
            ~ < k n { : f s ( __f5r_get at24 k ) = sum + sum * s s = k + k 1 }
            : f rms ( sqrt / sum # f n )
            ? < rms F5_TARGET_RMS {
                : f g / F5_TARGET_RMS ? > rms 1.0e-12 rms 1.0e-12
                = k 0
                ~ < k n { ( vec_set [f] at24 k * g ( __f5r_get at24 k ) ) = k + k 1 }
            } {}
            : ( Vec f ) mel ( log_mel_vocos at24 1024 F5_HOP 100 F5_SR )
            ( vec_free [f] at24 )
            : *F5Voice v # *F5Voice ( nurl_alloc Z F5Voice )
            = . v mel mel
            = . v frames / ( vec_len [f] mel ) 100
            = . v samples n
            = . v rms rms
            = . v text ( f5_fix_ref_text ref_text )
            ^ @ !*F5Voice String { T v }
        }
        F e → { ^ @ !*F5Voice String { F e } }
    }
}

// The voice directory the deployed service uses: config.json holds the
// transcript, reference.wav the recording.
@ f5_voice_open_dir s dir → !*F5Voice String {
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
    : !*F5Voice String r ( f5_voice_load ( string_data wavp ) ( string_data txt ) )
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
@ f5_duration * F5Voice v i gen_bytes i n_text f speed → i {
    : ~ f local speed
    ? < gen_bytes 10 { = local 0.3 } {}
    : i ref_audio_len / . v samples F5_HOP
    : i rb ( nurl_str_len ( string_data . v text ) )
    : ~ i d ref_audio_len
    ? > rb 0 {
        = d + ref_audio_len # i / * / # f ref_audio_len # f rb # f gen_bytes local
    } {}
    // at least the text's own length, and at least the conditioning, plus one
    : i floor1 + ? > n_text . v frames n_text . v frames 1
    ? < d floor1 { = d floor1 } {}
    ? > d 4096 { = d 4096 } {}
    ^ d
}

@ f5_ref_audio_len * F5Voice v → i { ^ / . v samples F5_HOP }

// ── one chunk ───────────────────────────────────────────────────────

@ f5_synth_chunk * F5Model m * Vocos vc * F5Voice v * F5Vocab vocab s gen_text
i steps f cfg f sway f speed i seed ( Vec f ) out → b {
    : ( Vec i ) ids ( vec_new [i] )
    : String full ( string_clone . v text )
    ( string_push_str full gen_text )
    ( f5_text_ids vocab ( string_data full ) ids )
    ( string_free full )
    : i gen_bytes ( nurl_str_len gen_text )
    : i duration ( f5_duration v gen_bytes ( vec_len [i] ids ) speed )
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
    ? < . v rms F5_TARGET_RMS {
        : f g / . v rms F5_TARGET_RMS
        = k 0
        ~ < k ( vec_len [f] out ) { ( vec_set [f] out k * g ( __f5r_get out k ) ) = k + k 1 }
    } {}
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
    : i mc ( f5_max_chars v speed )
    : ( Vec String ) chunks ( f5_chunk_text gen_text mc )
    : i nc ( vec_len [String] chunks )
    : i fade # i * fade_s # f F5_SR
    : ~ b ok T
    : ~ i k 0
    ~ < k nc {
        ?? ( vec_get [String] chunks k ) {
            T c → {
                : ( Vec f ) piece ( vec_new [f] )
                = ok & ok ( f5_synth_chunk m vc v vocab ( string_data c ) steps cfg sway speed
                + seed k piece )
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
