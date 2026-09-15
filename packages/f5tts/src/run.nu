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
            ? < rms0 F5_TARGET_RMS {
                : f g0 / F5_TARGET_RMS ? > rms0 1.0e-12 rms0 1.0e-12
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
    : ~ i prev ( __f5t_geti_pub starts 0 )
    : ~ i cur prev
    : ~ i k 1
    ~ < k ns {
        : i si ( __f5t_geti_pub starts k )
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
            : i s ( __f5t_geti_pub sil k )
            : i e ( __f5t_geti_pub sil + k 1 )
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
        ( vec_set [i] ns k - ( __f5t_geti_pub ns k ) keep_ms )
        ( vec_set [i] ns + k 1 + ( __f5t_geti_pub ns + k 1 ) keep_ms )
        = k + k 2
    }
    = k 0
    ~ < k - nn 2 {
        : i le ( __f5t_geti_pub ns + k 1 )
        : i ns2 ( __f5t_geti_pub ns + k 2 )
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
        : i a0 ( __f5t_geti_pub ns k )
        : i b0 ( __f5t_geti_pub ns + k 1 )
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
